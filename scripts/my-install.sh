#!/usr/bin/env bash
# Personal build of this fork: pulls the latest commits of the current branch, builds Coucou
# signed with your own "Apple Development" certificate (no iCloud, no provisioning profile)
# and installs it in /Applications, replacing the previous copy, then opens it.
#
#   ./scripts/my-install.sh            # pull + build + install
#   ./scripts/my-install.sh --no-pull  # build what is on disk
#
# One-time setup: Xcode → Settings → Accounts → your Apple ID → Manage Certificates → + →
# Apple Development. The same certificate keeps macOS permissions from one build to the next.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="fr.louisraille.NotchBuddy"
DERIVED="${HOME}/Library/Developer/Xcode/DerivedData/CoucouMine"
BUILT="${DERIVED}/Build/Products/Debug/Coucou.app"
TARGET="/Applications/Coucou.app"
export PATH="/opt/homebrew/bin:${PATH}"

if [ "${1:-}" != "--no-pull" ]; then
  echo "Pulling..."
  git -C "${REPO_ROOT}" pull --ff-only
fi

# The team is the OU of the Apple Development certificate in the login keychain.
CERT=$(security find-certificate -c "Apple Development" -p 2>/dev/null || true)
if [ -z "${CERT}" ]; then
  echo "No Apple Development certificate: Xcode → Settings → Accounts → Manage Certificates → + → Apple Development." >&2
  exit 1
fi
TEAM=$(printf '%s\n' "${CERT}" | openssl x509 -noout -subject -nameopt multiline | awk -F' = ' '/organizationalUnitName/ {print $2; exit}')
echo "Signing with team ${TEAM}"

echo "Building..."
cd "${REPO_ROOT}/NotchBuddy"
xcodegen >/dev/null
xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath "${DERIVED}" -quiet \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM="${TEAM}" PROVISIONING_PROFILE_SPECIFIER= \
  CODE_SIGN_ENTITLEMENTS=Resources/Coucou.entitlements SWIFT_OPTIMIZATION_LEVEL=-O \
  build

echo "Quitting Coucou..."
osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
for _ in 1 2 3 4 5; do pgrep -x Coucou >/dev/null || break; sleep 1; done
pkill -x Coucou 2>/dev/null || true

echo "Installing in ${TARGET}..."
rm -rf "${TARGET}"
ditto "${BUILT}" "${TARGET}"
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -u "${BUILT}" >/dev/null 2>&1 || true

open "${TARGET}"
echo "Done: $(git -C "${REPO_ROOT}" log --oneline -1)"
