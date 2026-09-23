// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "flutter_eml_msg_viewer",
  platforms: [
    .iOS("12.0")
  ],
  products: [
    .library(name: "flutter-eml-msg-viewer", targets: ["flutter_eml_msg_viewer"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "flutter_eml_msg_viewer",
      dependencies: []
    )
  ]
)
