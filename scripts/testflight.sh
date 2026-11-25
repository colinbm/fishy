#!/usr/bin/env bash
# Build, sign and upload an iOS (and optionally tvOS) app to App Store Connect for TestFlight.
#
# The same script in every app: keep the copies identical. What differs between apps lives in
# Config/testflight.conf (committed: PROJECT, SCHEME, optional PLATFORMS and Sentry settings) and
# Config/testflight.env (git-ignored: the App Store Connect API key; without it, the account
# signed in to Xcode is used).
#
# 1. Archives unsigned, with the next build number. Unsigned avoids needing a registered device for
#    a development profile; the export signs with the team's cloud-managed distribution certificate.
# 2. Ad-hoc signs every bundle with its entitlements, resolved as a signed build would have them
#    (variables filled in, application identifier added, push and iCloud set to production). Export
#    re-signs using the entitlements it finds in the archive's signature, and an unsigned archive has
#    none, so without this step capabilities are silently dropped from the upload.
# 3. Exports a signed .ipa locally and checks every entitlement survived. Signing drops one silently
#    when the App ID lacks that capability in the developer portal.
# 4. Exports again to upload, writes the new build number into the project (commit it), and uploads
#    debug symbols to Sentry when Config/testflight.conf sets SENTRY_PROJECT.
#
# PLATFORMS (default "iOS") lists the platforms to archive and upload, e.g. "iOS tvOS" for an app
# that also runs on Apple TV. Each platform runs steps 1-3, then the uploads, sharing one build number.
#
# Build numbers keep rising across versions (1.0 ended at build 10; 1.1 carried on from there), rather than
# Xcode's export restarting them at 1 for each version. The project file is only changed once the
# upload has succeeded, so a failed or interrupted run doesn't use one up.
#
# Usage: scripts/testflight.sh           archive, check and upload
#        scripts/testflight.sh --check   archive and check signing only: uploads and changes nothing
set -euo pipefail
cd "$(dirname "$0")/.."

CHECK_ONLY=false
case "${1:-}" in
  "") ;;
  --check) CHECK_ONLY=true ;;
  *) echo "Usage: scripts/testflight.sh [--check]" >&2; exit 2 ;;
esac

[ -f Config/testflight.conf ] || { echo "Config/testflight.conf is missing (it sets PROJECT and SCHEME)." >&2; exit 1; }
# shellcheck disable=SC1091
source Config/testflight.conf
: "${PROJECT:?Config/testflight.conf must set PROJECT}" "${SCHEME:?Config/testflight.conf must set SCHEME}"
PLATFORMS="${PLATFORMS:-iOS}"

AUTH=()
if [ -f Config/testflight.env ]; then
  # shellcheck disable=SC1091
  source Config/testflight.env
  [ -f "$ASC_KEY_PATH" ] || { echo "API key not found: $ASC_KEY_PATH" >&2; exit 1; }
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID")
  [ -n "${ASC_ISSUER_ID:-}" ] && AUTH+=(-authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "Using App Store Connect API key $ASC_KEY_ID"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Release settings for the scheme's app, and for every target (to find each embedded bundle's
# entitlements file and the build settings its entitlements refer to).
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination 'generic/platform=iOS' \
  -showBuildSettings -json 2>/dev/null > "$WORK/scheme.json"
xcodebuild -project "$PROJECT" -alltargets -configuration Release -showBuildSettings -json 2>/dev/null \
  > "$WORK/targets.json"
read -r TEAM VERSION BUILD < <(python3 -I - "$WORK/scheme.json" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1]))[0]["buildSettings"]
print(settings["DEVELOPMENT_TEAM"], settings["MARKETING_VERSION"], int(settings["CURRENT_PROJECT_VERSION"]))
PY
)
if $CHECK_ONLY; then NEXT=$BUILD; else NEXT=$((BUILD + 1)); fi
echo "$SCHEME $VERSION, build $BUILD → $NEXT (team $TEAM), for $PLATFORMS"

for PLATFORM in $PLATFORMS; do
PW="$WORK/$PLATFORM"
mkdir -p "$PW"
cp "$WORK/targets.json" "$PW/"
ARCHIVE="$PW/$SCHEME.xcarchive"
echo "== $PLATFORM"

xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination "generic/platform=$PLATFORM" \
  -archivePath "$ARCHIVE" CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION="$NEXT" archive -quiet
APP=$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "The archive has no app in it." >&2; exit 1; }

# Ad-hoc sign everything inside the app, innermost first: frameworks and libraries without
# entitlements (vendors' prebuilt ones arrive with their own signature, which export won't replace),
# then each app and extension with its entitlements. Writes what each bundle should end up with to
# expected.json for the check after signing, and the targets involved to targets.txt.
python3 -I - "$APP" "$PW" "$TEAM" "$BUILD" "$NEXT" <<'PY'
import json, os, plistlib, re, subprocess, sys

app, work, team, build, next_build = sys.argv[1:]
targets = {}
for entry in json.load(open(os.path.join(work, "targets.json"))):
    targets.setdefault(entry["target"], entry["buildSettings"])

def depth(path):
    return path.count(os.sep)

bundles, code = [], []
for root, dirs, files in os.walk(app):
    for name in dirs:
        if name.endswith((".app", ".appex")):
            bundles.append(os.path.join(root, name))
        elif name.endswith(".framework"):
            code.append(os.path.join(root, name))
    code += [os.path.join(root, name) for name in files if name.endswith(".dylib")]
bundles.append(app)

def fail(message):
    sys.exit(message)

def resolve(value, settings, where):
    """Fill in $(VAR) and ${VAR} as Xcode does when signing."""
    if isinstance(value, list):
        return [resolve(item, settings, where) for item in value]
    if isinstance(value, dict):
        return {key: resolve(item, settings, where) for key, item in value.items()}
    if not isinstance(value, str):
        return value
    def lookup(match):
        name = match.group(1) or match.group(2)
        if name in ("AppIdentifierPrefix", "TeamIdentifierPrefix"):
            return team + "."
        if name not in settings:
            fail(f"{where} uses $({name}), which isn't a Release build setting.")
        return settings[name]
    return re.sub(r"\$\(([A-Za-z0-9_]+)\)|\$\{([A-Za-z0-9_]+)\}", lookup, value)

os.makedirs(os.path.join(work, "entitlements"))
expected, used_targets, icloud = {}, [], False
for code_path in sorted(code, key=depth, reverse=True):
    subprocess.run(["codesign", "--force", "--sign", "-", code_path], check=True, capture_output=True)

for index, bundle in enumerate(sorted(bundles, key=depth, reverse=True)):
    relative = os.path.relpath(bundle, os.path.dirname(app))
    info = plistlib.load(open(os.path.join(bundle, "Info.plist"), "rb"))
    bundle_id, platform = info["CFBundleIdentifier"], info.get("DTPlatformName", "iphoneos")
    if info.get("CFBundleVersion") != next_build:
        fail(f"{relative} has build number {info.get('CFBundleVersion')}, not {next_build}: "
             "its Info.plist should use $(CURRENT_PROJECT_VERSION).")
    matches = [name for name, s in targets.items()
               if s.get("PRODUCT_BUNDLE_IDENTIFIER") == bundle_id
               and platform in s.get("SUPPORTED_PLATFORMS", "").split()]
    if len(matches) != 1:
        fail(f"Couldn't tell which target built {relative} ({bundle_id}, {platform}): {matches or 'none'}.")
    target = matches[0]
    settings = targets[target]
    if settings.get("CURRENT_PROJECT_VERSION") != build:
        fail(f"Target {target} has build number {settings.get('CURRENT_PROJECT_VERSION')}, but the app has {build}. "
             "Embedded targets must share the app's build number: make them match first.")
    used_targets.append(target)

    command = ["codesign", "--force", "--sign", "-"]
    source = settings.get("CODE_SIGN_ENTITLEMENTS")
    if source:
        wanted = resolve(plistlib.load(open(source, "rb")), settings, source)
        if "aps-environment" in wanted:
            wanted["aps-environment"] = "production"
        # The macOS spelling of the push entitlement, kept in multiplatform entitlements files for the
        # Mac build: signing for any other platform drops it.
        if platform != "macosx":
            wanted.pop("com.apple.developer.aps-environment", None)
        elif "com.apple.developer.aps-environment" in wanted:
            wanted["com.apple.developer.aps-environment"] = "production"
        expected[relative] = dict(wanted)
        if "com.apple.developer.icloud-container-identifiers" in wanted:
            icloud = True
            wanted["com.apple.developer.icloud-container-environment"] = "Production"
        wanted["application-identifier"] = f"{team}.{bundle_id}"
        wanted["com.apple.developer.team-identifier"] = team
        path = os.path.join(work, "entitlements", f"{index}.plist")
        plistlib.dump(wanted, open(path, "wb"))
        command += ["--entitlements", path, "--generate-entitlement-der"]
    subprocess.run(command + [bundle], check=True, capture_output=True)
    print(f"Signed {relative} ({target}){'' if source else ', no entitlements'}")

json.dump(expected, open(os.path.join(work, "expected.json"), "w"))
open(os.path.join(work, "targets.txt"), "w").write("\n".join(used_targets))
open(os.path.join(work, "icloud"), "w").write("yes" if icloud else "")
PY

# Export options for a destination: "export" writes the signed .ipa locally, "upload" sends it.
export_options() {
  local icloud=""
  [ -s "$PW/icloud" ] && icloud="<key>iCloudContainerEnvironment</key><string>Production</string>"
  cat > "$PW/ExportOptions-$1.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>automatic</string>
	<key>destination</key><string>$1</string>
	<key>manageAppVersionAndBuildNumber</key><false/>
	$icloud
</dict>
</plist>
PLIST
  echo "$PW/ExportOptions-$1.plist"
}

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$PW/signed" \
  -exportOptionsPlist "$(export_options export)" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} -quiet
IPA=$(find "$PW/signed" -maxdepth 1 -name '*.ipa' | head -1)
unzip -q "$IPA" -d "$PW/ipa"
python3 -I - "$PW/ipa/Payload" "$PW/expected.json" <<'PY'
import json, os, plistlib, subprocess, sys

payload, expected = sys.argv[1], json.load(open(sys.argv[2]))
problems = []
for relative, wanted in expected.items():
    signed = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", os.path.join(payload, relative)],
                            capture_output=True).stdout
    signed = plistlib.loads(signed) if signed.strip() else {}
    for key, value in wanted.items():
        have = signed.get(key)
        if have is None:
            problems.append(f"{relative} lost {key}")
        elif isinstance(value, list) and not set(map(str, value)) <= set(map(str, have)):
            problems.append(f"{relative} has {key} {have}, not {value}")
        elif not isinstance(value, (list, dict)) and have != value:
            problems.append(f"{relative} has {key} {have!r}, not {value!r}")
if problems:
    print("Signing dropped or changed entitlements:", *problems, sep="\n  ", file=sys.stderr)
    print("Add the missing capabilities to the App IDs in the developer portal, then try again.", file=sys.stderr)
    sys.exit(1)
print(f"Entitlements check out for {', '.join(expected) or 'the app (it has none)'}.")
PY

if $CHECK_ONLY; then
  echo "Archived and signed $SCHEME $VERSION ($NEXT) for $PLATFORM without problems."
  continue
fi

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$PW/export" \
  -exportOptionsPlist "$(export_options upload)" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} -quiet
echo "Uploaded $PLATFORM"
done

if $CHECK_ONLY; then
  echo "Nothing was uploaded or changed."
  exit 0
fi

# Record the new build number for the targets that were uploaded.
python3 -I - "$PROJECT" "$BUILD" "$NEXT" "$PW/targets.txt" <<'PY'
import os, re, sys

project, build, next_build, targets_file = sys.argv[1:]
targets = open(targets_file).read().split("\n")
pbxproj, xcproj = os.path.join(project, "project.pbxproj"), os.path.join(project, "project.xcproj")
if os.path.exists(pbxproj):
    # Every configuration with the old number: the app's targets share it.
    text, count = re.subn(rf"CURRENT_PROJECT_VERSION = {build};", f"CURRENT_PROJECT_VERSION = {next_build};",
                          open(pbxproj).read())
    path = pbxproj
elif os.path.exists(xcproj):
    # Only the uploaded targets: others (such as a Mac app) keep their own numbers. A target runs from
    # its name, followed by its id, to where the next target starts.
    text, count, path = open(xcproj).read(), 0, xcproj
    for target in targets:
        start = re.search(rf'"name": "{re.escape(target)}",\s*"id"', text).start()
        end = min(i for i in (text.find("\n    }, {", start), text.find("\n  ],", start)) if i >= 0)
        block, n = re.subn(rf'("CURRENT_PROJECT_VERSION": )"{build}"', rf'\g<1>"{next_build}"', text[start:end])
        text, count = text[:start] + block + text[end:], count + n
else:
    sys.exit(f"No project file found in {project}")
if count == 0:
    sys.exit(f"Uploaded, but couldn't find build number {build} in {path} to update: set it to {next_build} by hand.")
open(path, "w").write(text)
PY

# Debug symbols for Sentry, so crash reports show function names and line numbers. Optional: never
# fails the run. The token is read from the login keychain (so uploads don't need approval, and work
# while the Mac is locked); if that's empty or Sentry rejects it, it's fetched again from 1Password.
if [ -n "${SENTRY_PROJECT:-}" ]; then
  token_from_1password() {
    local token
    [ -n "${SENTRY_OP_REF:-}" ] || return 1
    token=$(op read ${SENTRY_OP_ACCOUNT:+--account "$SENTRY_OP_ACCOUNT"} "$SENTRY_OP_REF" 2>/dev/null) || return 1
    [ -n "$token" ] || return 1
    security add-generic-password -a "$USER" -s "$SENTRY_KEYCHAIN_ITEM" -l "$SCHEME Sentry upload token" -U -w "$token"
    printf '%s' "$token"
  }
  upload_symbols() {
    SENTRY_AUTH_TOKEN="$1" sentry-cli debug-files upload --org "$SENTRY_ORG" --project "$SENTRY_PROJECT" "$WORK"/*/*.xcarchive/dSYMs
  }
  if ! command -v sentry-cli >/dev/null; then
    echo "warning: sentry-cli isn't installed (brew install getsentry/tools/sentry-cli), so symbols weren't uploaded"
  else
    token="${SENTRY_AUTH_TOKEN:-$(security find-generic-password -a "$USER" -s "$SENTRY_KEYCHAIN_ITEM" -w 2>/dev/null || true)}"
    [ -n "$token" ] || token=$(token_from_1password || true)
    if [ -z "$token" ]; then
      echo "warning: no Sentry token (keychain empty and 1Password unavailable), so symbols weren't uploaded"
    elif ! upload_symbols "$token"; then
      echo "Sentry rejected the saved token; fetching the current one from 1Password"
      fresh=$(token_from_1password || true)
      if [ -n "$fresh" ] && [ "$fresh" != "$token" ] && upload_symbols "$fresh"; then
        echo "Symbols uploaded with the refreshed token"
      else
        echo "warning: couldn't upload symbols to Sentry; crash reports will show addresses"
      fi
    fi
  fi
fi

echo "Uploaded $SCHEME $VERSION ($NEXT) for $PLATFORMS. It appears in TestFlight once App Store Connect has processed it (usually 5–30 minutes)."
echo "Commit the build number change: git commit -am 'Build $NEXT'"
