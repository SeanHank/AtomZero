#!/usr/bin/env bash
#
# Package the Godot Linux export into .deb and .rpm distributables.
#
# Usage:
#   package_linux.sh <format> <version> <binary_path> [project_root]
#
#   format        "deb" or "rpm"
#   version       Game version string (e.g. 2026.6.30)
#   binary_path   Path to the exported Godot binary (e.g. dist/AtomZero.x86_64)
#   project_root  Project root directory (defaults to script's ../../)
#
# Output:
#   Writes the package to dist/AtomZero-<version>-linux.<format>
#
set -euo pipefail

FORMAT="${1:?Missing format: deb|rpm}"
VERSION="${2:?Missing version}"
BINARY_PATH="${3:?Missing binary path}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${4:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

GAME_NAME="AtomZero"
PKG_NAME="atomzero"
MAINTAINER="AtomLife Studio <contact@atomlife.studio>"
DESCRIPTION="AtomZero - an empty-shell, mod-driven game framework built on Godot 4.6.3."
HOMEPAGE="https://github.com/atomlife/atom-zero"
LICENSE="MIT"

if [ ! -f "$BINARY_PATH" ]; then
    echo "[package_linux] ERROR: Binary not found at $BINARY_PATH" >&2
    exit 1
fi

DIST_DIR="$PROJECT_ROOT/dist"
mkdir -p "$DIST_DIR"

case "$FORMAT" in
    deb)
        echo "[package_linux] Building .deb package..."
        BUILD_DIR="$(mktemp -d)"
        trap 'rm -rf "$BUILD_DIR"' EXIT

        INSTALL_DIR="$BUILD_DIR/usr/lib/$PKG_NAME"
        mkdir -p "$INSTALL_DIR"
        mkdir -p "$BUILD_DIR/usr/share/applications"
        mkdir -p "$BUILD_DIR/usr/share/icons/hicolor/scalable/apps"
        mkdir -p "$BUILD_DIR/DEBIAN"

        # Copy the binary and PCK (if separate)
        cp "$BINARY_PATH" "$INSTALL_DIR/"
        # Copy the .pck file if it exists alongside the binary
        BINARY_DIR="$(dirname "$BINARY_PATH")"
        BINARY_BASE="$(basename "$BINARY_PATH")"
        if [ -f "$BINARY_DIR/$GAME_NAME.pck" ]; then
            cp "$BINARY_DIR/$GAME_NAME.pck" "$INSTALL_DIR/"
        fi
        # Copy icon
        if [ -f "$PROJECT_ROOT/icon.svg" ]; then
            cp "$PROJECT_ROOT/icon.svg" "$INSTALL_DIR/"
            cp "$PROJECT_ROOT/icon.svg" "$BUILD_DIR/usr/share/icons/hicolor/scalable/apps/$PKG_NAME.svg"
        fi

        # Create writable directories (mods/, saves/, .cache/, logs/)
        # These are created at runtime in the user's data directory, but for portable
        # installs we also create empty placeholders next to the binary.
        mkdir -p "$INSTALL_DIR/mods" "$INSTALL_DIR/saves" "$INSTALL_DIR/.cache" "$INSTALL_DIR/logs"

        # Desktop entry
        cat > "$BUILD_DIR/usr/share/applications/$PKG_NAME.desktop" <<EOF
[Desktop Entry]
Name=$GAME_NAME
Comment=$DESCRIPTION
Exec=/usr/lib/$PKG_NAME/$BINARY_BASE
Icon=$PKG_NAME
Terminal=false
Type=Application
Categories=Game;
StartupWMClass=$GAME_NAME
EOF

        # Control file
        INSTALLED_SIZE="$(du -sk "$BUILD_DIR/usr" | cut -f1)"
        cat > "$BUILD_DIR/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $VERSION
Section: games
Priority: optional
Architecture: amd64
Installed-Size: $INSTALLED_SIZE
Maintainer: $MAINTAINER
Description: $DESCRIPTION
 AtomZero adopts an "Empty Shell + All-Mod-Driven" architecture. The base game
 only provides the Mod Loader core, event bus, virtual file system, and basic
 service interfaces; all gameplay is provided by Mods.
Homepage: $HOMEPAGE
Depends: libgl1, libx11-6, libxcursor1, libxinerama1, libxrandr2, libxi6, libpulse0
EOF

        # Postinst script to set permissions
        cat > "$BUILD_DIR/DEBIAN/postinst" <<EOF
#!/bin/sh
chmod 755 /usr/lib/$PKG_NAME/$BINARY_BASE
chmod -R 777 /usr/lib/$PKG_NAME/mods /usr/lib/$PKG_NAME/saves /usr/lib/$PKG_NAME/.cache /usr/lib/$PKG_NAME/logs
EOF
        chmod 755 "$BUILD_DIR/DEBIAN/postinst"

        # Build the .deb
        OUTPUT="$DIST_DIR/${GAME_NAME}-${VERSION}-linux.deb"
        dpkg-deb --build --root-owner-group "$BUILD_DIR" "$OUTPUT"
        echo "[package_linux] Wrote $OUTPUT"
        ;;

    rpm)
        echo "[package_linux] Building .rpm package..."
        BUILD_DIR="$(mktemp -d)"
        trap 'rm -rf "$BUILD_DIR"' EXIT

        # Create RPM build tree
        mkdir -p "$BUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

        # Create source tarball
        SOURCE_DIR="$BUILD_DIR/SOURCES/${PKG_NAME}-${VERSION}"
        mkdir -p "$SOURCE_DIR/usr/lib/$PKG_NAME"
        mkdir -p "$SOURCE_DIR/usr/share/applications"
        mkdir -p "$SOURCE_DIR/usr/share/icons/hicolor/scalable/apps"

        cp "$BINARY_PATH" "$SOURCE_DIR/usr/lib/$PKG_NAME/"
        BINARY_DIR="$(dirname "$BINARY_PATH")"
        BINARY_BASE="$(basename "$BINARY_PATH")"
        if [ -f "$BINARY_DIR/$GAME_NAME.pck" ]; then
            cp "$BINARY_DIR/$GAME_NAME.pck" "$SOURCE_DIR/usr/lib/$PKG_NAME/"
        fi
        if [ -f "$PROJECT_ROOT/icon.svg" ]; then
            cp "$PROJECT_ROOT/icon.svg" "$SOURCE_DIR/usr/lib/$PKG_NAME/"
            cp "$PROJECT_ROOT/icon.svg" "$SOURCE_DIR/usr/share/icons/hicolor/scalable/apps/${PKG_NAME}.svg"
        fi

        mkdir -p "$SOURCE_DIR/usr/lib/$PKG_NAME"/{mods,saves,.cache,logs}

        cat > "$SOURCE_DIR/usr/share/applications/${PKG_NAME}.desktop" <<EOF
[Desktop Entry]
Name=$GAME_NAME
Comment=$DESCRIPTION
Exec=/usr/lib/$PKG_NAME/$BINARY_BASE
Icon=$PKG_NAME
Terminal=false
Type=Application
Categories=Game;
StartupWMClass=$GAME_NAME
EOF

        tar -czf "$BUILD_DIR/SOURCES/${PKG_NAME}-${VERSION}.tar.gz" -C "$BUILD_DIR/SOURCES" "${PKG_NAME}-${VERSION}"

        # Build %files entries for files that may or may not be present.
        # .pck is separate by default but can be embedded in the binary;
        # icon.svg is always present in this project but we guard it anyway.
        RPM_PCK_ENTRY=""
        if [ -f "$BINARY_DIR/$GAME_NAME.pck" ]; then
            RPM_PCK_ENTRY="/usr/lib/$PKG_NAME/$GAME_NAME.pck"
        fi
        RPM_ICON_ENTRIES=""
        if [ -f "$PROJECT_ROOT/icon.svg" ]; then
            RPM_ICON_ENTRIES="/usr/lib/$PKG_NAME/icon.svg
/usr/share/icons/hicolor/scalable/apps/${PKG_NAME}.svg"
        fi

        # RPM spec
        cat > "$BUILD_DIR/SPECS/${PKG_NAME}.spec" <<EOF
Name:       $PKG_NAME
Version:    $VERSION
Release:    1
Summary:    $DESCRIPTION
License:    $LICENSE
URL:        $HOMEPAGE
Source0:    %{name}-%{version}.tar.gz
Requires:   mesa-libGL
Requires:   libX11
Requires:   libXcursor
Requires:   libXinerama
Requires:   libXrandr
Requires:   libXi
Requires:   pulseaudio-libs
AutoReqProv: no
%global _missing_build_ids_terminate_build 0

%description
$DESCRIPTION
AtomZero adopts an "Empty Shell + All-Mod-Driven" architecture.

%prep
%setup -q

%build

%install
cp -r * %{buildroot}/

%files
%dir /usr/lib/$PKG_NAME
/usr/lib/$PKG_NAME/$BINARY_BASE
$RPM_PCK_ENTRY
$RPM_ICON_ENTRIES
%dir /usr/lib/$PKG_NAME/mods
%dir /usr/lib/$PKG_NAME/saves
%dir /usr/lib/$PKG_NAME/.cache
%dir /usr/lib/$PKG_NAME/logs
/usr/share/applications/${PKG_NAME}.desktop

%post
chmod 755 /usr/lib/$PKG_NAME/$BINARY_BASE
chmod -R 777 /usr/lib/$PKG_NAME/mods /usr/lib/$PKG_NAME/saves /usr/lib/$PKG_NAME/.cache /usr/lib/$PKG_NAME/logs

%changelog
* $(date '+%a %b %d %Y') $MAINTAINER - $VERSION-1
- Automated build via CI
EOF

        # Build the RPM
        OUTPUT="$DIST_DIR/${GAME_NAME}-${VERSION}-linux.rpm"
        rpmbuild \
            --define "_topdir $BUILD_DIR" \
            --define "_rpmfilename %%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm" \
            -bb "$BUILD_DIR/SPECS/${PKG_NAME}.spec" || {
            echo "[package_linux] WARNING: rpmbuild failed (may not be available). Skipping .rpm." >&2
            exit 0
        }

        # Find and move the built RPM
        find "$BUILD_DIR/RPMS" -name "*.rpm" -exec cp {} "$OUTPUT" \;
        echo "[package_linux] Wrote $OUTPUT"
        ;;

    *)
        echo "[package_linux] ERROR: Unknown format '$FORMAT'. Use 'deb' or 'rpm'." >&2
        exit 1
        ;;
esac
