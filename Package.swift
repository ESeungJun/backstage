// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Backstage",
    platforms: [.macOS(.v14)],
    targets: [
        // 모델·해석·수집. 화면 없이 테스트할 수 있게 Foundation 만 쓴다.
        .target(name: "BackstageCore"),
        .executableTarget(name: "Backstage", dependencies: ["BackstageCore"]),
        .testTarget(name: "BackstageCoreTests", dependencies: ["BackstageCore"]),
    ]
)
