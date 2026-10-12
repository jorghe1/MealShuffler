#!/usr/bin/env bash
# Sets CFBundleVersion for a TestFlight upload to
#
#     max(latest build number in App Store Connect + 1, PROJECT_BUILD_NUMBER)
#
# PROJECT_BUILD_NUMBER is Codemagic's own per-app counter. It knows nothing about App Store
# Connect, so if the app is re-added to Codemagic, or builds are uploaded from Xcode in
# between, it lands on a number App Store Connect already has and the upload is rejected as a
# duplicate -- after a full signed build. Asking App Store Connect first makes the number
# monotonic where it matters; keeping PROJECT_BUILD_NUMBER as the floor means a lookup that
# returns something stale can never move the number backwards.
#
# Needs the App Store Connect API key that Codemagic's `app_store_connect` integration exports
# (APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_IDENTIFIER,
# APP_STORE_CONNECT_PRIVATE_KEY), which the `app-store-connect` CLI reads by itself.
#
# Optional:
#   APP_STORE_APPLE_ID  numeric Apple ID of the app (App Store Connect > App Information).
#                       Skips the bundle-id lookup when set.
#   BUNDLE_ID           defaults to no.mealshuffler.app.
#   DRY_RUN=1           print the number, do not run agvtool.
#
# If App Store Connect cannot be reached the build still goes ahead on PROJECT_BUILD_NUMBER,
# with a warning: a duplicate number fails loudly at upload, which is no worse than before.
set -euo pipefail

cd "${CM_BUILD_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

bundle_id="${BUNDLE_ID:-no.mealshuffler.app}"
floor="${PROJECT_BUILD_NUMBER:-${BUILD_NUMBER:-0}}"
case "$floor" in ''|*[!0-9]*) floor=0 ;; esac

warn() {
  echo "warning: $*" >&2
}

lookup_apple_id() {
  if [ -n "${APP_STORE_APPLE_ID:-}" ]; then
    printf '%s\n' "$APP_STORE_APPLE_ID"
    return 0
  fi
  local json
  json="$(app-store-connect apps list \
    --bundle-id-identifier "$bundle_id" \
    --strict-match-identifier \
    --json 2>/dev/null)" || return 1
  printf '%s' "$json" | python3 -c '
import json, sys
bundle = sys.argv[1]
try:
    apps = json.load(sys.stdin)
except ValueError:
    raise SystemExit(1)
if isinstance(apps, dict):
    apps = apps.get("data", [apps])
for app in apps:
    if (app.get("attributes") or {}).get("bundleId") == bundle and app.get("id"):
        print(app["id"])
        raise SystemExit(0)
raise SystemExit(1)
' "$bundle_id"
}

latest_testflight_number() {
  local apple_id="$1" out
  # --all-versions: the highest number across every version, not just the newest one. Older
  # CLI releases lack the flag, so fall back to the default (latest version) query.
  out="$(app-store-connect get-latest-testflight-build-number "$apple_id" --all-versions 2>/dev/null)" \
    || out="$(app-store-connect get-latest-testflight-build-number "$apple_id" 2>/dev/null)" \
    || return 1
  # The CLI prints the bare number; keep the last integer it printed in case of extra lines.
  printf '%s\n' "$out" | grep -Eo '^[0-9]+$' | tail -n 1
}

next="$floor"
source_note="PROJECT_BUILD_NUMBER"

if ! command -v app-store-connect >/dev/null 2>&1; then
  warn "app-store-connect CLI not found; using PROJECT_BUILD_NUMBER=$floor"
elif ! apple_id="$(lookup_apple_id)" || [ -z "$apple_id" ]; then
  warn "could not find the App Store Connect app for $bundle_id; using PROJECT_BUILD_NUMBER=$floor"
  warn "set APP_STORE_APPLE_ID in the ios_signing group to skip this lookup"
else
  if latest="$(latest_testflight_number "$apple_id")" && [ -n "$latest" ]; then
    candidate=$((latest + 1))
    echo "App Store Connect: latest TestFlight build for $bundle_id ($apple_id) is $latest"
    if [ "$candidate" -gt "$floor" ]; then
      next="$candidate"
      source_note="App Store Connect latest + 1"
    fi
  else
    # No builds yet is a legitimate answer for a brand-new app record.
    warn "no TestFlight build number returned for app $apple_id; using PROJECT_BUILD_NUMBER=$floor"
  fi
fi

if [ "$next" -lt 1 ]; then
  next=1
fi

echo "Build number: $next ($source_note; PROJECT_BUILD_NUMBER=$floor)"

if [ "${DRY_RUN:-0}" = "1" ]; then
  exit 0
fi

agvtool new-version -all "$next"

# Later steps (and the Codemagic UI's artifact names) can read the number that was used.
if [ -n "${CM_ENV:-}" ]; then
  echo "BUILD_NUMBER_USED=$next" >> "$CM_ENV"
fi
