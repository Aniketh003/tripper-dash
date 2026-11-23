// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TripperDash",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "TripperDashCore",
            targets: ["TripperDashCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TripperDashCore",
            path: "TripperDash",
            exclude: [
                "Info.plist",
                "Data/Sync/GoogleService-Info.plist.template"
            ]
        )
    ]
)
