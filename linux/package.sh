#!/usr/bin/env bash
# Build Linux distribution artifacts for Yomou Desktop.
#
# Usage:
#   ./linux/package.sh [target ...]
#
# Targets:
#   tarball        portable .tar.gz of the release bundle
#   deb            Debian/Ubuntu package (.deb)
#   rpm            Fedora/RHEL/openSUSE package (.rpm)
#   appimage       portable AppImage (downloads appimagetool on first run)
#   arch           Arch Linux package (.pkg.tar.zst) -- requires makepkg
#   flatpak-stage  stage a Flatpak manifest + bundle for flatpak-builder
#   all            tarball + deb + rpm + appimage
#
# Environment:
#   VERSION     package version (defaults to the version in pubspec.yaml)
#   BUNDLE_DIR  release bundle to package (default: build/linux/x64/release/bundle)
#   OUT_DIR     output directory (default: dist/)
#   APPIMAGETOOL path to a pre-downloaded appimagetool AppImage
#
# Requires "flutter build linux --release" to have produced the bundle first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${BUNDLE_DIR:-$ROOT/build/linux/x64/release/bundle}"
OUT="${OUT_DIR:-$ROOT/dist}"
APP_ID="com.stunna.manga_reader"
BIN_NAME="manga_reader"
DESKTOP_TEMPLATE="$ROOT/linux/com.stunna.yomou.desktop.in"
ICON_SOURCE="$ROOT/linux/icons/yomou.png"
HOMEPAGE="https://github.com/Hlomatsimaxwell/Yomou-Desktop"
MAINTAINER="Maxwell <hlomatsimaxwell@users.noreply.github.com>"

die() { echo "error: $*" >&2; exit 1; }

[ -x "$BUNDLE/$BIN_NAME" ] || die "Linux bundle missing at $BUNDLE (run: flutter build linux --release)"

if [ -z "${VERSION:-}" ]; then
  VERSION="$(sed -n 's/^version:[[:space:]]*\([0-9][^+[:space:]]*\).*/\1/p' "$ROOT/pubspec.yaml" | head -n1)"
fi
[ -n "$VERSION" ] || die "could not determine version (set VERSION=...)"
[[ "$VERSION" =~ ^[0-9] ]] || die "version must start with a digit: $VERSION"

mkdir -p "$OUT"

# Shared /usr layout used by every native package.
stage_tree() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p \
    "$dest/usr/lib/yomou" \
    "$dest/usr/bin" \
    "$dest/usr/share/applications" \
    "$dest/usr/share/icons/hicolor"

  cp -a "$BUNDLE/." "$dest/usr/lib/yomou/"
  ln -s ../lib/yomou/"$BIN_NAME" "$dest/usr/bin/$BIN_NAME"

  sed "s|__YOMOU_BIN__|/usr/bin/$BIN_NAME|g" \
    "$DESKTOP_TEMPLATE" \
    > "$dest/usr/share/applications/$APP_ID.desktop"

  local size dir
  for size in 48 128 256 512; do
    dir="$dest/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$dir"
    if command -v magick >/dev/null 2>&1; then
      magick "$ICON_SOURCE" -resize "${size}x${size}" "$dir/$APP_ID.png"
    elif command -v convert >/dev/null 2>&1; then
      convert "$ICON_SOURCE" -resize "${size}x${size}" "$dir/$APP_ID.png"
    else
      cp "$ICON_SOURCE" "$dir/$APP_ID.png"
    fi
  done
}

build_tarball() {
  local work
  work="$(mktemp -d)"
  mkdir -p "$work/Yomou-$VERSION"
  cp -a "$BUNDLE/." "$work/Yomou-$VERSION/"
  tar -C "$work" -czf "$OUT/Yomou-$VERSION-linux-x86_64.tar.gz" "Yomou-$VERSION"
  rm -rf "$work"
  echo "built $OUT/Yomou-$VERSION-linux-x86_64.tar.gz"
}

build_deb() {
  local stage="$OUT/.stage-deb"
  local tmp
  stage_tree "$stage"
  mkdir -p "$stage/DEBIAN"

  cat > "$stage/DEBIAN/control" <<EOF
Package: yomou
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Maintainer: $MAINTAINER
Installed-Size: $(du -sk "$stage" | cut -f1)
Depends: libgtk-3-0 | libgtk-3-0t64, libblkid1, liblzma5, libstdc++6, libc6
Homepage: $HOMEPAGE
Description: Yomou manga reader (desktop build)
 A desktop build of the Yomou manga reader: a Kotatsu-compatible
 manga reader with support for online sources.
EOF

  ( cd "$stage" &&
    find . -type f ! -path './DEBIAN/*' -printf '%P\0' |
      xargs -0 -r md5sum > DEBIAN/md5sums )

  local out="$OUT/yomou_${VERSION}_amd64.deb"
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb --build --root-owner-group "$stage" "$out" >/dev/null
  else
    # dpkg-deb is a thin wrapper around ar + tarballs; build it by hand so the
    # script still works on non-Debian build hosts (e.g. Fedora/Arch).
    tmp="$(mktemp -d)"
    printf '2.0\n' > "$tmp/debian-binary"
    tar -C "$stage/DEBIAN" -czf "$tmp/control.tar.gz" --owner=0 --group=0 .
    tar -C "$stage" -czf "$tmp/data.tar.gz" --owner=0 --group=0 --exclude='./DEBIAN*' .
    ( cd "$tmp" && ar rc "$out" debian-binary control.tar.gz data.tar.gz )
    rm -rf "$tmp"
  fi
  rm -rf "$stage"
  echo "built $out"
}

build_rpm() {
  command -v rpmbuild >/dev/null 2>&1 || die "rpmbuild not found (install rpm-build / rpm)"
  local stage="$OUT/.stage-rpm"
  local top
  stage_tree "$stage"
  top="$(mktemp -d)"
  mkdir -p "$top"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

  cat > "$top/SPECS/yomou.spec" <<EOF
%global __brp_check_rpaths %{nil}
%global debug_package %{nil}
Name: yomou
Version: $VERSION
Release: 1
Summary: Yomou manga reader (desktop build)
License: Apache-2.0
URL: $HOMEPAGE
BuildArch: x86_64
AutoReqProv: no
Requires: gtk3, libblkid, xz-libs, glibc, libstdc++

%description
A desktop build of the Yomou manga reader: a Kotatsu-compatible manga reader
with support for online sources.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a "$stage"/. %{buildroot}/

%files
/usr/lib/yomou
/usr/bin/$BIN_NAME
/usr/share/applications/$APP_ID.desktop
/usr/share/icons/hicolor
EOF

  rpmbuild -bb --quiet \
    --define "_topdir $top" \
    --define "_rpmdir $top/RPMS" \
    "$top/SPECS/yomou.spec" >/dev/null

  local built
  built="$(find "$top/RPMS" -name "yomou-$VERSION-1*.rpm" | head -n1)"
  [ -n "$built" ] || die "rpmbuild did not produce an rpm"
  mv "$built" "$OUT/"
  rm -rf "$top" "$stage"
  echo "built $OUT/$(basename "$built")"
}

build_appimage() {
  local appdir="$OUT/.AppDir"
  local tool="${APPIMAGETOOL:-}"
  rm -rf "$appdir"
  mkdir -p "$appdir/usr/lib/yomou" "$appdir/usr/bin"
  cp -a "$BUNDLE/." "$appdir/usr/lib/yomou/"
  ln -s ../lib/yomou/"$BIN_NAME" "$appdir/usr/bin/$BIN_NAME"

  cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib/yomou/lib:$HERE/usr/lib:${LD_LIBRARY_PATH:-}"
exec "$HERE/usr/lib/yomou/manga_reader" "$@"
EOF
  chmod +x "$appdir/AppRun"

  cp "$ICON_SOURCE" "$appdir/.DirIcon"
  cp "$ICON_SOURCE" "$appdir/$APP_ID.png"
  sed "s|__YOMOU_BIN__|$BIN_NAME|g" \
    "$DESKTOP_TEMPLATE" > "$appdir/$APP_ID.desktop"

  if [ -z "$tool" ]; then
    tool="$ROOT/.dart_tool/appimagetool"
    if [ ! -x "$tool" ]; then
      echo "downloading appimagetool..."
      mkdir -p "$(dirname "$tool")"
      curl -fsSL -o "$tool" \
        "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
      chmod +x "$tool"
    fi
  fi

  local out="$OUT/Yomou-$VERSION-x86_64.AppImage"
  ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream "$appdir" "$out"
  rm -rf "$appdir"
  echo "built $out"
}

build_arch() {
  command -v makepkg >/dev/null 2>&1 ||
    die "makepkg not found: run this target inside an Arch container (or on Arch)"

  local work
  work="$(mktemp -d)"
  sed "s|__YOMOU_BIN__|/usr/bin/$BIN_NAME|g" \
    "$DESKTOP_TEMPLATE" > "$work/$APP_ID.desktop"
  cp "$ICON_SOURCE" "$work/$APP_ID.png"

  cat > "$work/PKGBUILD" <<EOF
pkgname=yomou
pkgver=$VERSION
pkgrel=1
pkgdesc="Yomou manga reader (desktop build)"
arch=('x86_64')
url="$HOMEPAGE"
license=('Apache-2.0')
depends=('gtk3' 'xz' 'util-linux-libs' 'gcc-libs' 'glibc')
options=('!strip' '!debug')
package() {
  install -dm755 "\$pkgdir/usr/lib/yomou" "\$pkgdir/usr/bin"
  install -dm755 "\$pkgdir/usr/share/applications"
  install -dm755 "\$pkgdir/usr/share/icons/hicolor/512x512/apps"
  cp -a "$BUNDLE/." "\$pkgdir/usr/lib/yomou/"
  ln -s ../lib/yomou/$BIN_NAME "\$pkgdir/usr/bin/$BIN_NAME"
  install -Dm644 "$work/$APP_ID.desktop" "\$pkgdir/usr/share/applications/$APP_ID.desktop"
  install -Dm644 "$work/$APP_ID.png" "\$pkgdir/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"
}
EOF

  ( cd "$work" && makepkg -f --nodeps --noconfirm >/dev/null )
  local built
  built="$(find "$work" -maxdepth 1 -name '*.pkg.tar.zst' | head -n1)"
  [ -n "$built" ] || die "makepkg did not produce a package"
  cp "$built" "$OUT/"
  rm -rf "$work"
  echo "built $OUT/$(basename "$built")"
}

build_flatpak_stage() {
  local dir="${FLATPAK_STAGE_DIR:-$OUT/flatpak}"
  rm -rf "$dir"
  mkdir -p "$dir"
  cp -a "$BUNDLE" "$dir/bundle"
  sed "s|__YOMOU_BIN__|$BIN_NAME|g" \
    "$DESKTOP_TEMPLATE" > "$dir/$APP_ID.desktop"
  cp "$ICON_SOURCE" "$dir/$APP_ID.png"

  cat > "$dir/$APP_ID.yml" <<EOF
app-id: $APP_ID
runtime: org.freedesktop.Platform
runtime-version: '25.08'
sdk: org.freedesktop.Sdk
command: $BIN_NAME
finish-args:
  - --share=network
  - --share=ipc
  - --socket=wayland
  - --socket=fallback-x11
  - --device=dri
  - --filesystem=xdg-download
modules:
  - name: yomou
    buildsystem: simple
    build-commands:
      - mkdir -p /app/yomou /app/bin
      # A dir source unpacks its contents at the build root, so the release
      # tree (data/ lib/ manga_reader) is here directly.
      - cp -a data lib $BIN_NAME /app/yomou/
      - ln -s /app/yomou/$BIN_NAME /app/bin/$BIN_NAME
      - install -Dm644 $APP_ID.desktop /app/share/applications/$APP_ID.desktop
      - install -Dm644 $APP_ID.png /app/share/icons/hicolor/512x512/apps/$APP_ID.png
    sources:
      - type: dir
        path: bundle
      - type: file
        path: $APP_ID.desktop
      - type: file
        path: $APP_ID.png
EOF

  echo "staged Flatpak manifest at $dir/$APP_ID.yml"
}

main() {
  [ $# -gt 0 ] || set -- all
  local target
  for target in "$@"; do
    case "$target" in
      tarball) build_tarball ;;
      deb) build_deb ;;
      rpm) build_rpm ;;
      appimage) build_appimage ;;
      arch) build_arch ;;
      flatpak-stage) build_flatpak_stage ;;
      all)
        build_tarball
        build_deb
        build_rpm
        build_appimage
        ;;
      *) die "unknown target: $target" ;;
    esac
  done
}

main "$@"
