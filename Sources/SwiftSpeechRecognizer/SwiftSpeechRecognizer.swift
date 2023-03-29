#if os(macOS)
#error("This library is not compatible with macOS")
#endif

import Speech

public struct SwiftSpeechRecognizer {
    /// Receive every change about the authorization status of the Speech Recognition including microphone usage
    public var authorizationStatus: () -> AsyncStream<SFSpeechRecognizerAuthorizationStatus>

    /// Receive every single time the Speech Recognition engine recognize something. Including duplicates or `nil`.
    /// If you want a shortcut that already do the filter for you, use `newUtterancePublisher`
    public var recognizedUtterance: () -> AsyncStream<String?>

    /// Receive every changes about the Recognition status. Useful when you want to notify the user of
    /// the current Speech Recognition State
    public var recognitionStatus: () -> AsyncStream<SpeechRecognitionStatus>

    /// Receive whenever the availability of Speech Recognition services changes, this value will change
    /// for instance if the internet connection is lost
    public var isRecognitionAvailable: () -> AsyncStream<Bool>

    /// Shortcut to access with ease to the received new utterance (already filtered)
    public var newUtterance: () -> AsyncStream<String>

    /// Ask user if you can use Microphone for Speech Recognition
    /// You'll need to subscribe to `authorizationStatusPublisher` to know the user choice
    public var requestAuthorization: () -> Void

    /// Will trigger the Speech Recognition process. This method hide all the complexity of AVAudio interactions
    /// subscribe to `recognizedUtterancePublisher` or `newUtterancePublisher` depending on your needs
    public var startRecording: () throws -> Void

    /// Stop the Speech Recognition process manually
    public var stopRecording: () -> Void

    public init(
        authorizationStatus: @escaping () -> AsyncStream<SFSpeechRecognizerAuthorizationStatus>,
        recognizedUtterance: @escaping () -> AsyncStream<String?>,
        recognitionStatus: @escaping () -> AsyncStream<SpeechRecognitionStatus>,
        isRecognitionAvailable: @escaping () -> AsyncStream<Bool>,
        newUtterance: @escaping () -> AsyncStream<String>,
        requestAuthorization: @escaping () -> Void,
        startRecording: @escaping () -> Void,
        stopRecording: @escaping () -> Void
    ) {
        self.authorizationStatus = authorizationStatus
        self.recognizedUtterance = recognizedUtterance
        self.recognitionStatus = recognitionStatus
        self.isRecognitionAvailable = isRecognitionAvailable
        self.newUtterance = newUtterance
        self.requestAuthorization = requestAuthorization
        self.startRecording = startRecording
        self.stopRecording = stopRecording
    }
}

// See: https://developer.apple.com/documentation/speech/recognizing_speech_in_live_audio
private final class SpeechRecognitionSpeechEngine: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    var authorizationStatus: (SFSpeechRecognizerAuthorizationStatus) -> Void = { _ in }
    var recognizedUtterance: (String?) -> Void = { _ in }
    var recognitionStatus: (SpeechRecognitionStatus) -> Void = { _ in }

    /// Whenever the availability of speech recognition services changes, this value will change
    /// For instance if the internet connection is lost, isRecognitionAvailable will change to `false`
    var isRecognitionAvailable: (Bool) -> Void = { _ in }

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { @MainActor [weak self] authorizationStatus in
            self?.authorizationStatus(authorizationStatus)
        }
    }

    func startRecording() throws {
        guard !audioEngine.isRunning
        else { return stopRecording() }

        // Cancel the previous task if it's running.
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizedUtterance(nil)

        // Configure the audio session for the app.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let inputNode = audioEngine.inputNode

        // Create and configure the speech recognition request.
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest
        else { throw SpeechRecognitionEngineError.speechAudioBufferRecognitionRequestInitFailed }
        recognitionRequest.shouldReportPartialResults = true
        // Make some test, we could probably keep all speech recognition data on the devices
        // recognitionRequest.requiresOnDeviceRecognition = true

        guard let speechRecognizer = speechRecognizer
        else { throw SpeechRecognitionEngineError.speechRecognizerInitFailed }

        // Create a recognition task for the speech recognition session.
        // Keep a reference to the task so that it can be canceled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) {
            @MainActor [weak self] result, error in
            guard let self = self else { return }

            var isFinal = false

            if let result = result {
                // Update the text view with the results
                self.recognizedUtterance(result.bestTranscription.formattedString)
                isFinal = result.isFinal
            }

            if error != nil || isFinal {
                // Stop recognizing speech if there is a problem.
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                self.recognitionStatus(.stopped)
            }
        }

        // Configure the microphone input.
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, _) in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        recognitionStatus(.recording)
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recognitionStatus(.stopping)
        } else {
            recognitionStatus(.stopped)
        }
    }

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        isRecognitionAvailable(available)
    }
}

public extension SwiftSpeechRecognizer {
    static var live: Self {
        let engine = SpeechRecognitionSpeechEngine()
        let authorizationStatus = AsyncStream { continuation in
            engine.authorizationStatus = { continuation.yield($0) }
        }
        let recognizedUtterance = AsyncStream { continuation in
            engine.recognizedUtterance = { continuation.yield($0) }
        }
        let recognitionStatus = AsyncStream { continuation in
            engine.recognitionStatus = { continuation.yield($0) }
        }
        let isRecognitionAvailable = AsyncStream { continuation in
            engine.isRecognitionAvailable = { continuation.yield($0) }
        }
        let newUtterance = AsyncStream { continuation in
            Task {
                var lastUtterance: String? = nil
                for await utterance in recognizedUtterance.compactMap({ $0 }) where lastUtterance != utterance {
                    continuation.yield(utterance)
                    lastUtterance = utterance
                }
            }
        }

        return Self(
            authorizationStatus: { authorizationStatus },
            recognizedUtterance: { recognizedUtterance },
            recognitionStatus: { recognitionStatus },
            isRecognitionAvailable: { isRecognitionAvailable },
            newUtterance: { newUtterance },
            requestAuthorization: { engine.requestAuthorization() },
            startRecording: { engine.stopRecording() },
            stopRecording: { engine.stopRecording() }
        )
    }
}
