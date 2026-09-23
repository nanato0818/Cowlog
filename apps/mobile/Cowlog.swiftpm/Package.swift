// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Cowlog",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "Cowlog",
            targets: ["AppModule"],
            displayVersion: "0.1",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .pencil),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [.phone, .pad],
            supportedInterfaceOrientations: [.portrait]
        )
    ],
    targets: [
        .executableTarget(name: "AppModule", path: ".")
    ]
)
