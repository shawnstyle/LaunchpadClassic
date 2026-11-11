#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/ModuleCache
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/.build/ModuleCache" Sources/LauncherCore.swift Sources/InteractionPhysics.swift Tests/main.swift -o .build/core-tests
.build/core-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/.build/ModuleCache" -framework AppKit -framework SwiftUI Sources/LauncherCore.swift Sources/InteractionPhysics.swift Sources/LauncherModel.swift Sources/LauncherInteraction.swift Tests/LaunchBehaviorTests.swift -o .build/launch-behavior-tests
.build/launch-behavior-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/.build/ModuleCache" -framework AppKit -framework SwiftUI Sources/LauncherCore.swift Sources/InteractionPhysics.swift Sources/LauncherModel.swift Sources/LauncherInteraction.swift Tests/MotionTests.swift -o .build/motion-tests
.build/motion-tests
