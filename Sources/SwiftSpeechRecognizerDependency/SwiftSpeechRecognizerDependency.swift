#if os(macOS)
#error("This library is not compatible with macOS")
#endif

import Dependencies
import Speech
@_exported import SwiftSpeechRecognizer
import XCTestDynamicOverlay

extension SwiftSpeechRecognizer {
    static let test = Self(
        authorizationStatus: unimplemented("SwiftSpeechRecognizer.authorizationStatus"),
        recognizedUtterance: unimplemented("SwiftSpeechRecognizer.recognizedUtterance"),
        recognitionStatus: unimplemented("SwiftSpeechRecognizer.recognitionStatus"),
        isRecognitionAvailable: unimplemented("SwiftSpeechRecognizer.isRecognitionAvailable"),
        newUtterance: unimplemented("SwiftSpeechRecognizer.newUtterance"),
        requestAuthorization: unimplemented("SwiftSpeechRecognizer.requestAuthorization"),
        startRecording: unimplemented("SwiftSpeechRecognizer.startRecording"),
        stopRecording: unimplemented("SwiftSpeechRecognize.stopRecordingr")
    )
    static let preview = {
        var requestAuthorization: () -> Void = { }
        let authorizationStatus = AsyncStream { continuation in
            requestAuthorization = {
                Task {
                    try await Task.sleep(nanoseconds: 200_000_000)
                    continuation.yield(SFSpeechRecognizerAuthorizationStatus.authorized)
                }
            }
        }

        var startRecordingCallbacks: [() -> Void] = []
        var stopRecordingCallbacks: [() -> Void] = []

        let startRecording = {
            for startRecordingCallback in startRecordingCallbacks {
                startRecordingCallback()
            }
        }

        let stopRecording = {
            for stopRecordingCallback in stopRecordingCallbacks {
                stopRecordingCallback()
            }
        }

        let recognizedUtterance = AsyncStream<String?> { continuation in
            var recordingTask: Task<(), any Error>? = nil
            startRecordingCallbacks.append {
                continuation.yield(nil)
                recordingTask = Task {
                    var utterance: String?
                    for word in ["this", "is", "a", "preview", "speech", "recognition"] {
                        guard !Task.isCancelled else { return }
                        try await Task.sleep(nanoseconds: UInt64(50_000_000 * word.count))
                        if let existingUtterance = utterance {
                            utterance = "\(existingUtterance) \(word)"
                        } else {
                            utterance = word
                        }
                        continuation.yield(utterance)
                    }
                }
            }
            stopRecordingCallbacks.append {
                recordingTask?.cancel()
            }
        }

        let recognitionStatus = AsyncStream<SpeechRecognitionStatus> { continuation in
            continuation.yield(.notStarted)
            startRecordingCallbacks.append {
                continuation.yield(.recording)
            }
            stopRecordingCallbacks.append {
                continuation.yield(.stopping)
                Task {
                    try await Task.sleep(nanoseconds: UInt64(400_000_000))
                    continuation.yield(.stopped)
                }
            }
        }

        let isRecognitionAvailable = AsyncStream { continuation in continuation.yield(true) }
        let newUtterance = AsyncStream { continuation in
            Task {
                for await utterance in recognizedUtterance.compactMap({ $0 }) {
                    continuation.yield(utterance)
                }
            }
        }

        return Self(
            authorizationStatus: { authorizationStatus },
            recognizedUtterance: { recognizedUtterance },
            recognitionStatus: { recognitionStatus },
            isRecognitionAvailable: { isRecognitionAvailable },
            newUtterance: { newUtterance },
            requestAuthorization: requestAuthorization,
            startRecording: startRecording,
            stopRecording: stopRecording
        )
    }()
}

private enum SwiftSpeechRecognizerDependencyKey: DependencyKey {
    static let liveValue = SwiftSpeechRecognizer.live
    static let testValue = SwiftSpeechRecognizer.test
    static let previewValue = SwiftSpeechRecognizer.preview
}

public extension DependencyValues {
    var speechRecognizer: SwiftSpeechRecognizer {
        get { self[SwiftSpeechRecognizerDependencyKey.self] }
        set { self[SwiftSpeechRecognizerDependencyKey.self] = newValue }
    }
}

#if DEBUG
import SwiftUI

struct SwiftSpeechDependencyPreviews: PreviewProvider {
    static var previews: some View {
        Preview()
    }

    private struct Preview: View {
        @StateObject var model = SpeechRecognizerModel()

        var body: some View {
            VStack {
                Button {
                    if [.notStarted, .stopped].contains(model.recognitionStatus) {
                        model.startRecording()
                    } else {
                        model.stopRecording()
                    }
                } label: {
                    if [.notStarted, .stopped].contains(model.recognitionStatus) {
                        Text("Start recording").multilineTextAlignment(.center)
                    } else if model.recognitionStatus == .stopping {
                        Text("Stopping")
                    } else {
                        Text("Stop recording")
                    }
                }
                .disabled(model.recognitionStatus == .stopping)
                .padding()

                Text("Recognized utterance: \(model.newUtterance)")
                Text("Authorization Status: \(model.authorizationStatus.description)")
                Text("Speech Recognizer Status: \(model.recognitionStatus.description)")
            }
        }
    }

    private final class SpeechRecognizerModel: ObservableObject {
        @Dependency(\.speechRecognizer) var speechRecognizer

        @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
        @Published var recognitionStatus: SpeechRecognitionStatus = .notStarted
        @Published var newUtterance: String = ""

        func startRecording() {
            Task {
                for await authorizationStatus in speechRecognizer.authorizationStatus() {
                    self.authorizationStatus = authorizationStatus

                    if authorizationStatus == .authorized {
                        try! speechRecognizer.startRecording()
                    }
                }
            }

            Task {
                for await recognitionStatus in speechRecognizer.recognitionStatus() {
                    self.recognitionStatus = recognitionStatus
                }
            }

            Task {
                for await newUtterance in speechRecognizer.newUtterance() {
                    self.newUtterance = newUtterance
                }
            }

            if authorizationStatus != .authorized {
                speechRecognizer.requestAuthorization()
            } else {
                try! speechRecognizer.startRecording()
            }
        }

        func stopRecording() {
            speechRecognizer.stopRecording()
        }
    }
}

extension SFSpeechRecognizerAuthorizationStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notDetermined: return "not determined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .authorized: return "authorized"
        @unknown default: return "unknown!"
        }
    }
}
#endif
