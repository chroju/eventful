#!/bin/bash
# Build ntf, assemble Eventful.app, sign it, and register with LaunchServices.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Eventful.app
CERT_NAME="eventful-selfsigned"   # CN of the certificate created by make-cert.sh

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ntf "$APP/Contents/MacOS/ntf"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Sign with the self-signed certificate if present, otherwise ad-hoc.
# Ad-hoc signing changes binary identity on every rebuild, which can reset
# notification permission (tied to bundle id + signature) — fine for early
# development only.
if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  codesign --force --sign "$CERT_NAME" "$APP"
else
  echo "WARN: certificate '$CERT_NAME' not found; using ad-hoc signing." >&2
  echo "      Notification permission may reset on rebuild. Run scripts/make-cert.sh." >&2
  codesign --force --sign - "$APP"
fi

# Register with LaunchServices (skipping this can mean no notifications at all,
# or a stale cached icon/name).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

# Thin exec wrapper for PATH installation. A plain symlink does NOT work:
# NSBundle resolves the bundle from the symlink's location and finds nothing
# (verified on macOS 26). exec-ing the real path keeps bundle resolution intact.
cat > build/ntf <<EOF
#!/bin/sh
exec "$(pwd)/$APP/Contents/MacOS/ntf" "\$@"
EOF
chmod +x build/ntf

echo "OK: $APP"
echo "install example: ln -sf \"$(pwd)/build/ntf\" ~/bin/ntf"
