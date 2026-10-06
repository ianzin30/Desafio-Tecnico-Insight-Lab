#!/bin/sh
# Registers the built app with the desktop (menu entry and icon) for the
# current user. On Wayland, GNOME and KDE take the icon from a .desktop file
# named after the application ID; the window icon set by the app is ignored.
#
#   flutter build linux --release
#   linux/packaging/install-desktop-entry.sh    # from flutter/
set -eu

APP_ID=dev.insightlab.messenger_app
ARCH=$(uname -m | sed 's/aarch64/arm64/; s/x86_64/x64/')
BUNDLE=$(cd "$(dirname "$0")/../.." && pwd)/build/linux/$ARCH/release/bundle
DATA=${XDG_DATA_HOME:-$HOME/.local/share}

if [ ! -x "$BUNDLE/insight_lab" ]; then
  echo "$BUNDLE/insight_lab not found: run 'flutter build linux --release' first." >&2
  exit 1
fi

mkdir -p "$DATA/icons/hicolor/512x512/apps" "$DATA/applications"
cp "$BUNDLE/data/app_icon.png" "$DATA/icons/hicolor/512x512/apps/$APP_ID.png"
cat > "$DATA/applications/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Insight Lab
Comment=Matrix messaging client
Exec="$BUNDLE/insight_lab"
Icon=$APP_ID
StartupWMClass=$APP_ID
Categories=Network;InstantMessaging;
Terminal=false
EOF
command -v update-desktop-database >/dev/null &&
  update-desktop-database "$DATA/applications" 2>/dev/null || true
echo "Installed $DATA/applications/$APP_ID.desktop"
