#!/bin/bash
# مثبّت تطبيقات منيب — Munib Apps Installer (Mac)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/hamzamunibwork/munib-content/main/tools/install.sh | bash -s arabic
#   ... | bash -s <app> [ipad|mac]     app = library | arabic | english | notes | all
#   ... | bash -s setup                creates the «Munib Installer» app in Applications (buttons for every app)
# ipad: builds and installs on the connected iPad/iPhone (cable, unlocked). mac: installs the Mac version.
BASE="https://raw.githubusercontent.com/hamzamunibwork/munib-content/main/tools"
OWNER="hamzamunibwork"
W="$HOME/MunibApps"; mkdir -p "$W"
APP="${1:-}"; TARGET="${2:-ipad}"
say() { echo "* $*"; }
die() { echo; echo "ERROR: $*"; echo; [ -t 0 ] || exec </dev/tty; echo "Press Enter to close"; read -r _; exit 1; }
[ "$(uname)" = "Darwin" ] || die "This installer runs on a Mac."

# قائمة التطبيقات من الخادم (تُضاف إليها التطبيقات الجديدة بسطر واحد)
LIST=$(curl -fsSL "$BASE/apps.txt?t=$(date +%s)") || die "No internet connection."
row() { echo "$LIST" | grep -v '^#' | awk -F'|' -v k="$1" '$1==k'; }

# ---------- setup: برنامج الماك ----------
if [ "$APP" = "setup" ]; then
  say "Creating «Munib Installer» in Applications..."
  AS=$(mktemp /tmp/munib_inst.XXXX).applescript
  printf '\xEF\xBB\xBF' > "$AS"   # UTF-8 حتى تظهر العربية سليمة
  cat >> "$AS" <<'APPLESCRIPT'
on run
	set base to "https://raw.githubusercontent.com/hamzamunibwork/munib-content/main/tools"
	try
		set raw to do shell script "curl -fsSL '" & base & "/apps.txt' | grep -v '^#' | awk -F'|' '{print $1\"|\"$2}'"
	on error
		display dialog "لا يوجد اتصال بالإنترنت." buttons {"حسنًا"} with title "مثبّت تطبيقات منيب"
		return
	end try
	set keysList to {}
	set namesList to {}
	repeat with ln in paragraphs of raw
		set AppleScript's text item delimiters to "|"
		set parts to text items of ln
		set AppleScript's text item delimiters to ""
		if (count of parts) ≥ 2 then
			set end of keysList to item 1 of parts
			set end of namesList to item 2 of parts
		end if
	end repeat
	set end of keysList to "all"
	set end of namesList to "كل التطبيقات"
	set pick to choose from list namesList with title "مثبّت تطبيقات منيب" with prompt "اختر التطبيق:" OK button name "التالي" cancel button name "إلغاء"
	if pick is false then return
	set k to ""
	repeat with i from 1 to count of namesList
		if item i of namesList is (item 1 of pick) then set k to item i of keysList
	end repeat
	set d to button returned of (display dialog "أين تريد تثبيت «" & (item 1 of pick) & "»؟" & return & return & "للآيباد أو الآيفون: صِله بالكابل وافتح قفله." buttons {"إلغاء", "على هذا الماك", "على الآيباد / الآيفون"} default button 3 with title "مثبّت تطبيقات منيب")
	if d is "إلغاء" then return
	if d is "على هذا الماك" then
		set t to "mac"
	else
		set t to "ipad"
	end if
	tell application "Terminal"
		activate
		do script "curl -fsSL '" & base & "/install.sh' | bash -s " & k & " " & t
	end tell
end run
APPLESCRIPT
  DEST="/Applications/Munib Installer.app"
  rm -rf "$DEST"
  osacompile -o "$DEST" "$AS" 2>/dev/null || { DEST="$HOME/Applications/Munib Installer.app"; mkdir -p "$HOME/Applications"; rm -rf "$DEST"; osacompile -o "$DEST" "$AS" || die "Could not create the app."; }
  rm -f "$AS"
  say "Done: $DEST"; say "You can drag it to the Dock. Opening it now..."
  open "$DEST"; exit 0
fi

[ -z "$APP" ] && die "Write the app name: library, arabic, english, notes or all."
if [ "$APP" = "all" ]; then
  for k in $(echo "$LIST" | grep -v '^#' | cut -d'|' -f1); do bash -c "$(curl -fsSL "$BASE/install.sh?t=$(date +%s)")" _ "$k" "$TARGET" </dev/tty || true; done
  exit 0
fi
R=$(row "$APP"); [ -z "$R" ] && die "Unknown app: $APP"
IFS='|' read -r KEY NAME REPO ITAG IASSET KIND PROJ SCHEME PRODUCT BUNDLE MTAG MASSET <<< "$R"
say "Munib Apps Installer: $KEY ($TARGET)"; echo

# ---------- أداة GitHub (للمستودعات الخاصة): تُنزَّل وتُسجَّل مرة واحدة ----------
GH=$(command -v gh)
if [ -z "$GH" ]; then
  GH="$HOME/Library/Caches/munib-gh/bin/gh"
  if [ ! -x "$GH" ]; then
    say "Downloading the GitHub tool (once)..."
    ARCH=$( [ "$(uname -m)" = "arm64" ] && echo arm64 || echo amd64 )
    URL=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep -o "https://[^\"]*macOS_${ARCH}\.zip" | head -1)
    [ -z "$URL" ] && die "Could not find the GitHub tool. Check the internet."
    rm -rf /tmp/munib_gh && mkdir -p /tmp/munib_gh && curl -fsSL "$URL" -o /tmp/munib_gh/gh.zip && unzip -oq /tmp/munib_gh/gh.zip -d /tmp/munib_gh || die "Download failed."
    mkdir -p "$HOME/Library/Caches/munib-gh" && cp -R /tmp/munib_gh/gh_*/bin "$HOME/Library/Caches/munib-gh/" || die "Could not install the GitHub tool."
  fi
fi
if ! "$GH" auth status -h github.com >/dev/null 2>&1; then
  echo; say "First time only: sign in to GitHub (the account that owns your apps)."
  say "Choose: GitHub.com > HTTPS > Login with a web browser. Copy the code, press Enter, paste it in the browser."
  "$GH" auth login -h github.com -p https -w </dev/tty || die "GitHub sign-in did not finish. Run again."
fi
dl() {  # dl <tag> <pattern> <dir>
  local tag="$1" pat="$2" dir="$3"; rm -rf "$dir"; mkdir -p "$dir"
  if [ "$tag" = "latest" ]; then "$GH" release download -R "$OWNER/$REPO" -p "$pat" -D "$dir" --clobber
  else "$GH" release download "$tag" -R "$OWNER/$REPO" -p "$pat" -D "$dir" --clobber; fi
}

# ---------- على هذا الماك ----------
if [ "$TARGET" = "mac" ]; then
  say "Downloading the Mac version..."
  dl "$MTAG" "$MASSET" "$W/dl-$KEY" || die "No Mac version found for this app yet. (Run its build-desktop workflow on GitHub.)"
  DMG=$(ls "$W/dl-$KEY"/*.dmg | head -1); [ -f "$DMG" ] || die "Mac file not found."
  xattr -cr "$DMG" 2>/dev/null
  MP=$(hdiutil attach -nobrowse -noverify -noautoopen "$DMG" | tail -1 | sed 's/.*\(\/Volumes\/.*\)/\1/')
  SRC=$(ls -d "$MP"/*.app 2>/dev/null | head -1); [ -d "$SRC" ] || { hdiutil detach -quiet "$MP"; die "No app inside the file."; }
  APPN=$(basename "$SRC"); DEST="/Applications/$APPN"
  say "Installing $APPN..."
  pkill -f "$DEST/Contents/MacOS" 2>/dev/null; rm -rf "$DEST"
  ditto "$SRC" "$DEST" || { hdiutil detach -quiet "$MP"; die "Could not copy to Applications."; }
  hdiutil detach -quiet "$MP"
  xattr -cr "$DEST"; codesign --force --deep --sign - "$DEST" >/dev/null 2>&1
  open "$DEST"; echo; say "DONE: $APPN is installed on this Mac."; exit 0
fi

# ---------- على الآيباد / الآيفون ----------
command -v xcodebuild >/dev/null && xcodebuild -version >/dev/null 2>&1 || die "Xcode is needed. Install it from the App Store, open it once, then run again."
FREE=$(df -g "$HOME" | awk 'NR==2{print $4}'); [ "${FREE:-0}" -lt 5 ] && die "Only ${FREE} GB free; at least 5 GB needed."
TEAM_F="$HOME/.munib-team"; TEAM=$(cat "$TEAM_F" 2>/dev/null)
[ -z "$TEAM" ] && TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')
[ -z "$TEAM" ] && die "No Apple account in Xcode. Open Xcode > Settings > Apple Accounts, add your Apple ID, then run again."
echo "$TEAM" > "$TEAM_F"

J=/tmp/munib_devices.json; xcrun devicectl list devices --json-output "$J" >/dev/null 2>&1
DEV=$(/usr/bin/python3 - "$J" <<'PY'
import json, sys
try: ds = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception: ds = []
for d in ds:
    h = d.get("hardwareProperties", {}); c = d.get("connectionProperties", {})
    if h.get("platform") == "iOS" and c.get("pairingState") == "paired" and c.get("tunnelState") != "unavailable":
        print(d["identifier"] + "|" + d.get("deviceProperties", {}).get("name", "iPad")); break
PY
)
[ -z "$DEV" ] && die "iPad/iPhone not found. Connect it with the cable, unlock it, tap Trust if asked, and run again."
UDID=${DEV%%|*}; DNAME=${DEV#*|}; say "Device: $DNAME"

SRCD="$W/$KEY"; BUILD="$W/build-$KEY"
if [ "$KIND" = "xcodegen" ]; then
  # المكتبة: من نسختك المحلية (GitHub Desktop) إن وُجدت، فهي الأسرع
  for d in "$HOME/Documents/GitHub/$REPO" "$HOME/GitHub/$REPO" "$HOME/Desktop/$REPO" "$HOME/Documents/$REPO" "$HOME/$REPO"; do
    CMD=$(ls "$d"/ios/*.command 2>/dev/null | grep -v 'جهز' | head -1)
    if [ -n "$CMD" ]; then say "Using your local copy: $d"; exec bash "$CMD" </dev/tty; fi
  done
fi
say "Downloading the latest iPad project..."
dl "$ITAG" "$IASSET" "$W/dl-$KEY" || die "The iPad project is not ready yet. On GitHub open the repo > Actions > build-ipad > Run workflow, wait for the green tick, then run again."
rm -rf "$SRCD" && mkdir -p "$SRCD" && unzip -oq "$W/dl-$KEY/$IASSET" -d "$SRCD" || die "Could not unpack the project."
cd "$SRCD" || die "Folder error."
# Xcode الحديث لا يقبل مكتبات تطلب iOS أقدم من 15، فيُرفع الحد الأدنى فيها إلى 15
find . -name project.pbxproj -exec sed -i '' -E 's/IPHONEOS_DEPLOYMENT_TARGET = (1[0-4]|[0-9])(\.[0-9]+)*;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g' {} + 2>/dev/null
if [ "$KIND" = "cap" ]; then BLD=(-workspace "$PROJ"); else BLD=(-project "$PROJ"); fi
say "Building $NAME for $DNAME (1-3 minutes)... If the Mac asks for its password, type it and press Always Allow."
xcodebuild "${BLD[@]}" -scheme "$SCHEME" -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic build > /tmp/munib_build.log 2>&1 \
  || { tail -25 /tmp/munib_build.log; die "Build failed. Take a photo of this window and send it."; }
APPP="$BUILD/Build/Products/Debug-iphoneos/$PRODUCT"; [ -d "$APPP" ] || die "Built app not found."
say "Installing on $DNAME..."
xcrun devicectl device install app --device "$UDID" "$APPP" >/tmp/munib_install.log 2>&1 \
  || { tail -8 /tmp/munib_install.log; die "Install failed. Unlock the iPad and run again."; }
xcrun devicectl device process launch --device "$UDID" "$BUNDLE" >/dev/null 2>&1 \
  || say "If the app does not open: on the iPad go to Settings > General > VPN & Device Management > your Apple ID > Trust."
echo; say "DONE: $NAME is installed on $DNAME."
say "(With a free Apple ID it works for 7 days; with a paid developer account, one year. Run this again to renew.)"
