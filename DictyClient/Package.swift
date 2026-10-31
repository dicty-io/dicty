// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DictyClient",
    platforms: [.macOS(.v14)],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "Dicty",
            path: "Sources/DictyClient",
            resources: [
                .process("dicty_tray_icon.png"),
                .process("dicty_logo.png"),
                .process("dicty_logo.svg"),
                .process("Icon-macOS-Default-1024.png"),
                .process("Icon-macOS-Dark-1024.png"),
                .process("uk_flag.jpg"),
                .process("multilingual.jpg"),
                .process("mermaid.min.js"),
                .process("flag_us.png"),
                .process("flag_gb.png"),
                .process("flag_de.png"),
                .process("flag_ru.png"),
                .process("flag_es.png"),
                .process("flag_ua.png")
            ]
        ),
        .testTarget(
            name: "DictyClientTests",
            dependencies: ["Dicty"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
