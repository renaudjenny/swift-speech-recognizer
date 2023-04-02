import Foundation

public enum SpeechRecognitionStatus {
    case notStarted
    case recording
    case stopping
    case stopped
}

extension SpeechRecognitionStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notStarted: return "not started"
        case .recording: return "recording"
        case .stopping: return "stopping"
        case .stopped: return "stopped"
        }
    }
}
