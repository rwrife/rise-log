#!/usr/bin/env bash
# Workspace layout seam guard (issue #5).
#
# Asserts that:
# 1. FermentWorkspaceLayout is the SOLE view reading horizontalSizeClass.
# 2. FermentWorkspaceLayout delegates to FermentWorkspaceRouting.route.
# 3. No other view composes JarWallView and CultureDetailView.
# 4. Zero references to fold/hinge SDK names appear in app or package sources.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "--- verifying workspace layout seam ---"

# 1. horizontalSizeClass check
size_class_files=$(grep -rn "horizontalSizeClass" RiseLog/ --include="*.swift" -l || true)
if [ "$size_class_files" != "RiseLog/FermentWorkspaceLayout.swift" ]; then
  echo "::error::horizontalSizeClass must only be read in RiseLog/FermentWorkspaceLayout.swift, found: $size_class_files"
  exit 1
fi
echo "horizontalSizeClass restricted to FermentWorkspaceLayout: PASS"

# 2. Routing call check
grep -q "FermentWorkspaceRouting\.route" RiseLog/FermentWorkspaceLayout.swift || {
  echo "::error::FermentWorkspaceLayout must call FermentWorkspaceRouting.route"
  exit 1
}
echo "FermentWorkspaceLayout calls FermentWorkspaceRouting.route: PASS"

# 3. Jar-wall/detail composition confined to the seam
for symbol in "JarWallView(" "CultureDetailView("; do
  hits=$(grep -Rsn "$symbol" RiseLog --include="*.swift" | grep -v "RiseLog/FermentWorkspaceLayout.swift" || true)
  if [ -n "$hits" ]; then
    echo "::error::$symbol must only appear in FermentWorkspaceLayout.swift"
    echo "$hits"
    exit 1
  fi
done
echo "Jar-wall/detail composition confined to FermentWorkspaceLayout: PASS"

# 4. No forbidden fold tokens in app or package sources
FORBIDDEN=(
  "FoldStatus"
  "foldStatus"
  "FoldState"
  "foldState"
  "HingeAngle"
  "hingeAngle"
  "isUnfolded"
  "unfoldState"
  "SystemFold"
  "spanningMode"
)

for token in "${FORBIDDEN[@]}"; do
  hits=$(grep -rn "$token" RiseLog/ Packages/RiseKit/Sources/ --include="*.swift" || true)
  if [ -n "$hits" ]; then
    echo "::error::Forbidden fold token '$token' found:"
    echo "$hits"
    exit 1
  fi
done
echo "Zero forbidden fold tokens found: PASS"

echo "Workspace layout seam guard: PASS"
