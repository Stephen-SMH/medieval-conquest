#!/bin/sh
# Export the game and pack each build for a release, into dist/.
#
#   tools/export.sh web windows linux macos android
#
# Needs the export templates (tools/fetch_godot_templates.py). GODOT names the
# Godot binary (default: godot). Android signs with the release keystore given by
# GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD; without one it makes a
# debug build with Godot's debug keystore.
set -eu
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
version=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot)
name="medieval-conquest-$version"
mkdir -p dist

export_preset() {  # mode, preset name, output file
	rm -rf "$(dirname "$3")"
	mkdir -p "$(dirname "$3")"
	"$GODOT" --headless "--export-$1" "$2" "$3"
	if [ ! -s "$3" ]; then
		echo "export of $2 failed: no $3" >&2
		exit 1
	fi
}

for platform in "$@"; do
	echo "== $platform $version"
	case $platform in
	web)
		export_preset release Web build/web/index.html
		(cd build/web && zip -qr "../../dist/$name-web.zip" .)
		;;
	windows)
		export_preset release "Windows Desktop" build/windows/medieval-conquest.exe
		(cd build/windows && zip -qr "../../dist/$name-windows.zip" .)
		;;
	linux)
		export_preset release Linux build/linux/medieval-conquest.x86_64
		(cd build/linux && zip -qr "../../dist/$name-linux.zip" .)
		;;
	macos)
		export_preset release macOS build/macos/medieval-conquest.zip
		cp build/macos/medieval-conquest.zip "dist/$name-macos.zip"
		;;
	android)
		if [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
			export_preset release Android build/android/medieval-conquest.apk
		else
			export_preset debug Android build/android/medieval-conquest.apk
		fi
		cp build/android/medieval-conquest.apk "dist/$name-android.apk"
		;;
	*)
		echo "unknown platform: $platform" >&2
		exit 1
		;;
	esac
done
ls -la dist
