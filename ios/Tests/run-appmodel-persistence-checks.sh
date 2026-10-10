#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/unplugged-appmodel-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
sources=(
  "$repo_root"/ios/Unplugged/State/AppModel*.swift
  "$repo_root/ios/Unplugged/State/Persistence.swift"
  "$repo_root/ios/Unplugged/State/ChargingSession.swift"
  "$repo_root/ios/Unplugged/Models/Models.swift"
  "$repo_root/ios/Unplugged/Models/Provenance.swift"
  "$repo_root/ios/Unplugged/Models/OperatorCatalog.swift"
  "$repo_root/ios/Unplugged/Models/StationFeed.swift"
  "$repo_root/ios/Unplugged/Models/StationQuery.swift"
  "$repo_root/ios/Unplugged/Models/DemoData.swift"
  "$repo_root/ios/Unplugged/Models/VehicleCatalog.swift"
  "$repo_root/ios/Unplugged/State/SpotHold.swift"
  "$repo_root/ios/Unplugged/UI/Localization.swift"
  "$repo_root"/ios/Unplugged/Logic/*.swift
  "$repo_root/ios/Tests/AppModelPersistenceChecks.swift"
)
xcrun swiftc -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$check_dir/module-cache" \
  "${sources[@]}" -o "$check_dir/AppModelPersistenceChecks"
# The car catalog is read from next to the executable (Bundle.main).
cp "$repo_root/ios/Unplugged/Data/vehicles.json" "$check_dir/"
"$check_dir/AppModelPersistenceChecks"
