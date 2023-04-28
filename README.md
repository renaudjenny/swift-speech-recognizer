# SwiftSpeechRecognizer

This package contains some very straightforward wrappers around around Speech Recognition part of SFSpeechRecognizer to allow you using this with ease.

* `SwiftSpeechRecognizer` Using **Swift Concurrency** with `async` `await`, a couple of `AsyncStream`
* `SwiftSpeechRecognizerDependency` A wrapper around the library above facilitating the integration with [Point-Free Dependencies](https://github.com/pointfreeco/swift-dependencies) library or a project made with The Composable Architecture (TCA).
* `SwiftSpeechCombine` the OG library still available in this package

## Modern concurrency usage

TODO

## Point-Free Dependency usage

Add `@Dependency(\.speechRecognizer) var speechRecognizer` in your `Reducer`, you will have access to all functions mentioned above.

### Example

```swift
import ComposableArchitecture
import Speech
import SwiftSpeechRecognizerDependency

public struct SpeechRecognizer: ReducerProtocol {
    public struct State: Equatable {
        public var status: SpeechRecognitionStatus = .notStarted
        public var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
        public var utterance: String?

        public init(
            status: SpeechRecognitionStatus = .notStarted,
            authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined,
            utterance: String? = nil
        ) {
            self.status = status
            self.authorizationStatus = authorizationStatus
            self.utterance = utterance
        }
    }

    public enum Action: Equatable {
        case buttonTapped
        case startRecording
        case stopRecording
        case setStatus(SpeechRecognitionStatus)
        case setUtterance(String?)
        case requestAuthorization
        case setAuthorizationStatus(SFSpeechRecognizerAuthorizationStatus)
        case cancel
    }

    @Dependency(\.speechRecognizer) var speechRecognizer

    public init() {}

    private enum AuthorizationStatusTaskID {}
    private enum RecognitionStatusTaskID {}
    private enum NewUtteranceTaskID {}

    public func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
        switch action {
        case .buttonTapped:
            switch state.status {
            case .recording, .stopping:
                return stopRecording(state: &state)
            case .notStarted, .stopped:
                return startRecording(state: &state)
            }
        case .startRecording:
            return startRecording(state: &state)
        case .stopRecording:
            return stopRecording(state: &state)
        case let .setStatus(status):
            state.status = status
            switch status {
            case .recording, .stopping:
                state.utterance = nil
            case .notStarted, .stopped:
                break
            }
            return .none
        case let .setUtterance(utterance):
            state.utterance = utterance
            return .none
        case let .setAuthorizationStatus(authorizationStatus):
            state.authorizationStatus = authorizationStatus
            switch authorizationStatus {
            case .authorized:
                return startRecording(state: &state)
            case .notDetermined:
                return requestAuthorization(state: &state)
            default: break
            }
            return .none
        case .requestAuthorization:
            return requestAuthorization(state: &state)
        case .cancel:
            return .cancel(ids: [AuthorizationStatusTaskID.self, RecognitionStatusTaskID.self, NewUtteranceTaskID.self])
        }
    }

    private func startRecording(state: inout State) -> EffectTask<Action> {
        guard state.authorizationStatus == .authorized
        else { return requestAuthorization(state: &state) }
        do {
            try speechRecognizer.startRecording()
            return .merge(
                .run(operation: { send in
                    for await recognitionStatus in speechRecognizer.recognitionStatus() {
                        await send(.setStatus(recognitionStatus))
                    }
                })
                .cancellable(id: RecognitionStatusTaskID.self),
                .run(operation: { send in
                    for await newUtterance in speechRecognizer.newUtterance() {
                        await send(.setUtterance(newUtterance))
                    }
                })
                .cancellable(id: NewUtteranceTaskID.self)
            )
        } catch {
            return stopRecording(state: &state)
        }
    }

    private func stopRecording(state: inout State) -> EffectTask<Action> {
        speechRecognizer.stopRecording()
        return .none
    }

    private func requestAuthorization(state: inout State) -> EffectTask<Action> {
        speechRecognizer.requestAuthorization()
        return .run { send in
            for await authorizationStatus in speechRecognizer.authorizationStatus() {
                await send(.setAuthorizationStatus(authorizationStatus))
            }
        }
        .cancellable(id: AuthorizationStatusTaskID.self)
    }
}
```

## Combine usage

You can instantiate/inject `SpeechRecognitionEngine` object, it has this behavior

* `func requestAuthorization()`: call this method when you want to ask user if you can use Speech Recognition. Please, follow Apple Human Guidelines recommendations: [Asking Permission to Use Speech Recognition](https://developer.apple.com/documentation/speech/asking_permission_to_use_speech_recognition)
  * subscribe to `authorizationStatusPublisher` to know when and what's the user decision (see below)
* `func startRecording() throws`: call this method when you want to start the speech recognition, all the complexity with `AVAudioEngine` is hidden behind this function.
  * subscribe to `recognizedUtterancePublisher` or `newUtterancePublisher` depending on your needs. See below the difference
* `func stopRecording()`: call this method when you want the speech recognition to stop

* `var authorizationStatusPublisher`: subscribe to this to know what's the current authorization status of the speech recognition (this authorization include the microphone usage)
* `var recognizedUtterancePublisher`: subscribe to this to know when a `String` is recognized
* `var isRecognitionAvailablePublisher`: subscribe to this to know when the recognition status changed. It could be:
  * `notStarted`: no recognition has started yet for the session
  * `recording`: the recognition is processing
  * `stopping`: a stop recognition has just been triggered
  * `stopped`: the recognition is stopped, and is ready to start the next recognition
* `var isRecognitionAvailablePublisher`: subscribe to this to know when the Speech Recognition is available on the device (like if the internet connection allows the Speech Recognition to be processed)
* `var newUtterancePublisher`: subscribe to this if you're only interested in "new" actual utterance. It's actually a shortcut of `recognizedUtterancePublisher` while it removes duplicates and only take an actual String (so it's never `nil`)

### Example

```swift
import Combine
import Speech
import SwiftSpeechCombine

let engine: SpeechRecognitionEngine = SpeechRecognitionSpeechEngine()
var cancellables = Set<AnyCancellable>()

// Only start to record if you're authorized to do so!
func speechRecognitionStatusChanged(authorizationStatus: SFSpeechRecognizerAuthorizationStatus) {
    guard authorizationStatus == .authorized
    else { return }

    do {
        try engine.startRecording()

        engine.newUtterancePublisher
            .sink { newUtterance in
                // Do whatever you want with the recognized utterance...
                print(newUtterance)
            }
            .store(in: &cancellables)

        engine.recognitionStatusPublisher
            .sink { status in
                // Very useful to notify the user of the current status
                setTheButtonState(status: status)
            }
            .store(in: &cancellables)
    } catch {
        print(error)
        engine.stopRecording()
    }
}

func setTheButtonState(status: SpeechRecognitionStatus) {
    switch status {
    case .notStarted: print("The button is ready to be tapped")
    case .recording: print("The button is showing a progress spinner")
    case .stopping: print("The button is disabled")
    case .stopped: print("The button is ready to be tapped for a new recognition")
    }
}

engine.requestAuthorization()

engine.authorizationStatusPublisher
    .compactMap { $0 }
    .sink { authorizationStatus in
        speechRecognitionStatusChanged(authorizationStatus: authorizationStatus)
    }
    .store(in: &cancellables)
```

## Installation

### Xcode

You can add SwiftSpeechCombine to an Xcode project by adding it as a package dependency.

1. From the **File** menu, select **Swift Packages › Add Package Dependency...**
2. Enter "https://github.com/renaudjenny/SwiftSpeechCombine" into the package repository URL test field

### As package dependency

Edit your `Package.swift` to add this library.

```swift
let package = Package(
    ...
    dependencies: [
        .package(url: "https://github.com/renaudjenny/SwiftSpeechCombine", from: "0.0.1"),
        ...
    ],
    targets: [
        .target(
            name: "<Your project name>",
            dependencies: ["SwiftSpeechCombine"]),
        ...
    ]
)
```

## App using this library

* [📲 Tell Time UK](https://apps.apple.com/gb/app/tell-time-uk/id1496541173): https://github.com/renaudjenny/telltime
