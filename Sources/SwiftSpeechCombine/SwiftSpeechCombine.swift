import Combine
import Speech
import SwiftSpeechRecognizer

public protocol SpeechRecognitionEngine {
    /// Publish every change about the authorization status of the Speech Recognition including microphone usage
    var authorizationStatusPublisher: AnyPublisher<SFSpeechRecognizerAuthorizationStatus?, Never> { get }

    /// Publish every single time the Speech Recognition engine recognize something. Including duplicates or `nil`.
    /// If you want a shortcut that already do the filter for you, use `newUtterancePublisher`
    var recognizedUtterancePublisher: AnyPublisher<String?, Never> { get }

    /// Publish every changes about the Recognition status. Useful when you want to notify the user of
    /// the current Speech Recognition State
    var recognitionStatusPublisher: AnyPublisher<SpeechRecognitionStatus, Never> { get }

    /// Publish whenever the availability of Speech Recognition services changes, this value will change
    /// for instance if the internet connection is lost
    var isRecognitionAvailablePublisher: AnyPublisher<Bool, Never> { get }

    /// Shortcut to access with ease to the published new utterance (already filtered)
    var newUtterancePublisher: AnyPublisher<String, Never> { get }

    /// Ask user if you can use Microphone for Speech Recognition
    /// You'll need to subscribe to `authorizationStatusPublisher` to know the user choice
    func requestAuthorization()

    /// Will trigger the Speech Recognition process. This method hide all the complexity of AVAudio interactions
    /// subscribe to `recognizedUtterancePublisher` or `newUtterancePublisher` depending on your needs
    func startRecording() throws

    /// Stop the Speech Recognition process manually
    func stopRecording()
}

// See: https://developer.apple.com/documentation/speech/recognizing_speech_in_live_audio
public final class SpeechRecognitionSpeechEngine: NSObject, ObservableObject, SFSpeechRecognizerDelegate, SpeechRecognitionEngine {
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus?
    @Published var recognizedUtterance: String?
    @Published var recognitionStatus: SpeechRecognitionStatus = .notStarted

    /// Whenever the availability of speech recognition services changes, this value will change
    /// For instance if the internet connection is lost, isRecognitionAvailable will change to `false`
    @Published var isRecognitionAvailable: Bool = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    public override init() { }

    public func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authorizationStatus in
            DispatchQueue.main.async { [weak self] in
                self?.authorizationStatus = authorizationStatus
            }
        }
    }

    public func startRecording() throws {
        guard !audioEngine.isRunning
        else { return stopRecording() }

        // Cancel the previous task if it's running.
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizedUtterance = nil

        // Configure the audio session for the app.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let inputNode = audioEngine.inputNode

        // Create and configure the speech recognition request.
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest
        else {
            throw SpeechRecognitionEngineError.speechAudioBufferRecognitionRequestInitFailed
        }
        recognitionRequest.shouldReportPartialResults = true
        // Make some test, we could probably keep all speech recognition data on the devices
        // recognitionRequest.requiresOnDeviceRecognition = true

        guard let speechRecognizer = speechRecognizer
        else { throw SpeechRecognitionEngineError.speechRecognizerInitFailed }

        // Create a recognition task for the speech recognition session.
        // Keep a reference to the task so that it can be canceled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                var isFinal = false

                if let result = result {
                    // Update the text view with the results
                    self.recognizedUtterance = result.bestTranscription.formattedString
                    isFinal = result.isFinal
                    print("Text \(result.bestTranscription.formattedString)")
                }

                if error != nil || isFinal {
                    // Stop recognizing speech if there is a problem.
                    self.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)

                    self.recognitionRequest = nil
                    self.recognitionTask = nil

                    self.recognitionStatus = .stopped
                }
            }
        }

        // Configure the microphone input.
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, _) in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        recognitionStatus = .recording
    }

    public func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recognitionStatus = .stopping
        } else {
            recognitionStatus = .stopped
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate
public extension SpeechRecognitionSpeechEngine {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        isRecognitionAvailable = available
    }
}

// MARK: - SpeechRecognitionEngine
public extension SpeechRecognitionSpeechEngine {
    var authorizationStatusPublisher: AnyPublisher<SFSpeechRecognizerAuthorizationStatus?, Never> {
        $authorizationStatus.eraseToAnyPublisher()
    }

    var recognizedUtterancePublisher: AnyPublisher<String?, Never> {
        $recognizedUtterance.eraseToAnyPublisher()
    }

    var recognitionStatusPublisher: AnyPublisher<SpeechRecognitionStatus, Never> {
        $recognitionStatus.eraseToAnyPublisher()
    }

    var isRecognitionAvailablePublisher: AnyPublisher<Bool, Never> {
        $isRecognitionAvailable.eraseToAnyPublisher()
    }

    var newUtterancePublisher: AnyPublisher<String, Never> {
        $recognizedUtterance
            .removeDuplicates()
            .compactMap({ $0 })
            .eraseToAnyPublisher()
    }
}
