// swift-tools-version: 6.0
// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

// macOS 26 wegen `glassEffect`, `GlassEffectContainer` und den Knopfstilen
// `.glass`/`.glassProminent`.
let package = Package(
    name: "Unterrichtsplanung",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Unterrichtsplanung",
            path: "Quellen/Unterrichtsplanung",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "Pruefungen",
            dependencies: ["Unterrichtsplanung"],
            path: "Pruefungen",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
