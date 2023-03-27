import Dependencies
import Speech
import SwiftSpeechRecognizer
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
                    var utterance: String? = ""
                    for word in ["this", "is", "a", "preview", "speech", "recognition"] {
                        guard !Task.isCancelled else { return }
                        try await Task.sleep(nanoseconds: UInt64(100_000_000 * word.count))
                        utterance = (utterance ?? "") + word
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
