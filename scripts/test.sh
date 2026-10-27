#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
swiftc -parse-as-library -swift-version 6 \
  Sources/Core/Domain.swift Sources/Core/Preferences.swift Sources/Core/AssociationService.swift Sources/Manager/AppStore.swift \
  Sources/Models/FileAssociation.swift Sources/Services/AppScanner.swift Sources/Services/ExtensionDescriptionDB.swift Sources/Services/ResourceHelper.swift \
  Sources/Routing/BrowserService.swift Sources/Routing/WindowAccess.swift Sources/Routing/RouterModel.swift Sources/Routing/RouteOption.swift \
  Tests/OpenlyTests/RoutingTests.swift Tests/OpenlyTests/SystemChecks.swift -o .build/checks/routing-checks
.build/checks/routing-checks "$@"
python3 scripts/test-bridge.py
