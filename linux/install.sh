#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="${ROOT_DIR}/build/linux/x64/release/bundle"
APP_NAME="com.stunna.manga_reader"
BIN_NAME="manga_reader"

if [ ! -x "${BUNDLE_DIR}/${BIN_NAME}" ]; then
  echo "Build the Linux app first: flutter build linux" >&2
  exit 1
fi

INSTALL_ROOT="${HOME}/.local/share/${APP_NAME}"
BIN_DIR="${HOME}/.local/bin"
ICON_DIR="${HOME}/.local/share/icons/hicolor"
DESKTOP_DIR="${HOME}/.local/share/applications"

mkdir -p "${INSTALL_ROOT}" "${BIN_DIR}" "${DESKTOP_DIR}" "${ICON_DIR}"

cp -r "${BUNDLE_DIR}/"* "${INSTALL_ROOT}/"
chmod -R u+rX "${INSTALL_ROOT}"
ln -sf "${INSTALL_ROOT}/${BIN_NAME}" "${BIN_DIR}/${BIN_NAME}"

for size in 48 128 256 512; do
  dest="${ICON_DIR}/${size}x${size}/apps"
  mkdir -p "${dest}"
  if command -v magick >/dev/null 2>&1; then
    magick "${ROOT_DIR}/linux/icons/yomou.png" -resize "${size}x${size}" "${dest}/${APP_NAME}.png"
  elif command -v convert >/dev/null 2>&1; then
    convert "${ROOT_DIR}/linux/icons/yomou.png" -resize "${size}x${size}" "${dest}/${APP_NAME}.png"
  else
    cp "${ROOT_DIR}/linux/icons/yomou.png" "${dest}/${APP_NAME}.png"
  fi
done

# Expand the launch path into a valid .desktop entry.
sed "s|__YOMOU_BIN__|${BIN_DIR}/${BIN_NAME}|g" \
  "${ROOT_DIR}/linux/com.stunna.yomou.desktop.in" \
  > "${DESKTOP_DIR}/${APP_NAME}.desktop"
chmod 644 "${DESKTOP_DIR}/${APP_NAME}.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${DESKTOP_DIR}" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q "${HOME}/.local/share/icons/hicolor" || true
fi

echo "Installed Yomou to ${INSTALL_ROOT}"
echo "Launcher: ${DESKTOP_DIR}/${APP_NAME}.desktop"
echo "Make sure ${BIN_DIR} is in PATH for CLI launches."