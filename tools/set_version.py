#!/usr/bin/env python3
"""Stamp a version into the project and its export presets.

    python3 tools/set_version.py 2.1.0        # or v2.1.0, as a git tag reads
    python3 tools/set_version.py 2.1.0-dev.abc1234

Sets application/config/version (shown on the Credits screen), the Android
version name and code, and the macOS version. The Android version code must
grow with each release, so it is made from the numbers: 2.1.3 -> 20103.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def version_code(version):
	numbers = [int(n) for n in re.findall(r"\d+", version.split("-")[0].split("+")[0])[:3]]
	numbers += [0] * (3 - len(numbers))
	return numbers[0] * 10000 + numbers[1] * 100 + numbers[2]


def set_key(text, key, value, path):
	pattern = re.compile(r"^%s=.*$" % re.escape(key), re.M)
	if not pattern.search(text):
		sys.exit("%s: no %s line" % (path.name, key))
	return pattern.sub(lambda _: "%s=%s" % (key, value), text)


def main(args):
	if len(args) != 1:
		sys.exit(__doc__)
	version = args[0].removeprefix("v")
	if not re.match(r"^\d+\.\d+\.\d+", version):
		sys.exit("not a version: " + args[0])
	short = re.match(r"^\d+\.\d+\.\d+", version).group(0)

	project = ROOT / "project.godot"
	project.write_text(set_key(project.read_text(), "config/version", '"%s"' % version, project))

	presets = ROOT / "export_presets.cfg"
	text = presets.read_text()
	text = set_key(text, "version/name", '"%s"' % version, presets)
	text = set_key(text, "version/code", str(version_code(version)), presets)
	text = set_key(text, "application/short_version", '"%s"' % short, presets)
	text = set_key(text, "application/version", '"%s"' % short, presets)
	presets.write_text(text)
	print("version", version, "android code", version_code(version))


if __name__ == "__main__":
	main(sys.argv[1:])
