// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-speech-recognizer",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "SwiftSpeechRecognizer",targets: ["SwiftSpeechRecognizer"]),
//        .library(name: "SwiftSpeechRecognizerDependency",targets: ["SwiftSpeechRecognizerDependency"]),
        .library(name: "SwiftSpeechCombine",targets: ["SwiftSpeechCombine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "0.2.0"),
    ],
    targets: [
        .target(name: "SwiftSpeechRecognizer", dependencies: []),
//        .target(
//            name: "SwiftSpeechRecognizerDependency",
//            dependencies: [
//                .product(name: "Dependencies", package: "swift-dependencies"),
//                "SwiftSpeechRecognizer",
//            ]
//        ),
        .testTarget(name: "SwiftSpeechRecognizerTests", dependencies: ["SwiftSpeechRecognizer"]),
        .target(name: "SwiftSpeechCombine", dependencies: []),
    ]
)
