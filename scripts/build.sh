#!/bin/bash
#
# Compile HookBar en Debug et la lance : pour tester une modification.
# N'affiche que les erreurs et avertissements du compilateur (à copier-coller en cas de souci).
#
# Prérequis : brew install xcodegen
# Usage     : ./scripts/build.sh          compile et lance
#             ./scripts/build.sh --test   lance aussi les tests

set -uo pipefail
cd "$(dirname "$0")/.."

DERIVED="build/debug"
LOG="build/build.log"

step() { printf '\n\033[1;33m▸ %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

command -v xcodegen >/dev/null || fail "xcodegen est introuvable. Installe-le avec : brew install xcodegen"
mkdir -p build

step "Projet Xcode"
xcodegen generate --quiet || fail "xcodegen a échoué."

step "Compilation (Debug)"
xcodebuild -project HookBar.xcodeproj -scheme HookBar -configuration Debug \
    -destination "platform=macOS" -derivedDataPath "$DERIVED" build > "$LOG" 2>&1
STATUS=$?
grep -E "(error|warning): " "$LOG" | grep -v "^ld: warning" | sort -u
[ $STATUS -eq 0 ] || fail "Compilation échouée (journal complet : $LOG)."

if [ "${1:-}" = "--test" ]; then
    step "Tests"
    xcodebuild -project HookBar.xcodeproj -scheme HookBar -destination "platform=macOS" \
        -derivedDataPath "$DERIVED" test 2>&1 | grep -E "(✔|✘|error:|Test run|passed|failed)" | tail -40
fi

step "Lancement"
APP="$DERIVED/Build/Products/Debug/HookBar.app"
pkill -x HookBar 2>/dev/null && sleep 0.5
open "$APP"
echo "HookBar est dans la barre de menus."
