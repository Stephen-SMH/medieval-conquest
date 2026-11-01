#!/bin/sh
# Renders the Android launcher icons in assets/android/ from icon.svg (macOS).
# Run from anywhere: tools/make_android_icons.sh
#
# Godot's SVG rasteriser (ThorVG) drops <text>, so the glyph is drawn by
# Quick Look (WebKit) as black on white and turned into an alpha mask by
# tools/make_android_icons.gd, which also renders the box and writes:
#   icon_192.png             legacy launcher icon (whole icon)
#   icon_foreground_432.png  adaptive icon foreground (glyph only; launchers
#                            mask the 432 px layer down to its middle ~264 px)
#   icon_background_432.png  adaptive icon background (solid box colour)
#   icon_monochrome_432.png  themed icon for Android 13+ (glyph only)
set -e
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sed -E -e 's|<rect[^>]*/>||' \
	-e 's|fill="#[0-9a-fA-F]+"|fill="#000"|' \
	-e 's|width="128" height="128"|width="432" height="432" viewBox="0 0 128 128"|' \
	icon.svg > "$tmp/glyph.svg"
qlmanage -t -s 432 -o "$tmp" "$tmp/glyph.svg" >/dev/null 2>&1
godot --headless --script tools/make_android_icons.gd -- "$tmp/glyph.svg.png" 2>&1 | grep '^wrote'
