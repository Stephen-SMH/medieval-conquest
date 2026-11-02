#!/usr/bin/env python3
"""Install some of Godot's export templates without downloading all of them.

The official templates come as one 1.3 GB zip. The download server allows
range requests, so this reads the zip's directory and then only the members
asked for, and writes them where Godot looks for templates.

    python3 tools/fetch_godot_templates.py 4.7.2 web_nothreads_release.zip linux_release.x86_64
    python3 tools/fetch_godot_templates.py 4.7.2 --list
"""

import io
import os
import pathlib
import platform
import sys
import urllib.request
import zipfile

URL = "https://github.com/godotengine/godot-builds/releases/download/{0}-stable/Godot_v{0}-stable_export_templates.tpz"
BLOCK = 8 * 1024 * 1024


class RangeFile(io.RawIOBase):
	"""A read-only, seekable file over HTTP that fetches big blocks on demand."""

	def __init__(self, url):
		with urllib.request.urlopen(urllib.request.Request(url, method="HEAD")) as reply:
			self.url = reply.url
			self.size = int(reply.headers["Content-Length"])
		self.pos = 0
		self.start = 0
		self.block = b""

	def seekable(self):
		return True

	def readable(self):
		return True

	def tell(self):
		return self.pos

	def seek(self, offset, whence=io.SEEK_SET):
		self.pos = {io.SEEK_SET: 0, io.SEEK_CUR: self.pos, io.SEEK_END: self.size}[whence] + offset
		return self.pos

	def read(self, n=-1):
		if n is None or n < 0:
			n = self.size - self.pos
		n = min(n, self.size - self.pos)
		if n <= 0:
			return b""
		if not (self.start <= self.pos and self.pos + n <= self.start + len(self.block)):
			self.start = self.pos
			end = min(self.size, self.pos + max(n, BLOCK)) - 1
			request = urllib.request.Request(self.url, headers={"Range": "bytes=%d-%d" % (self.pos, end)})
			with urllib.request.urlopen(request) as reply:
				self.block = reply.read()
		at = self.pos - self.start
		self.pos += n
		return self.block[at:at + n]


def templates_dir(version):
	if os.environ.get("GODOT_TEMPLATES_DIR"):
		root = pathlib.Path(os.environ["GODOT_TEMPLATES_DIR"])
	elif platform.system() == "Darwin":
		root = pathlib.Path.home() / "Library/Application Support/Godot/export_templates"
	elif platform.system() == "Windows":
		root = pathlib.Path(os.environ["APPDATA"]) / "Godot/export_templates"
	else:
		root = pathlib.Path(os.environ.get("XDG_DATA_HOME", pathlib.Path.home() / ".local/share")) / "godot/export_templates"
	return root / ("%s.stable" % version)


def main(args):
	if len(args) < 2:
		sys.exit(__doc__)
	version, names = args[0], args[1:]
	archive = zipfile.ZipFile(RangeFile(URL.format(version)))
	if names == ["--list"]:
		for info in archive.infolist():
			print("%10.1f MB  %s" % (info.file_size / 1e6, info.filename.removeprefix("templates/")))
		return
	out = templates_dir(version)
	out.mkdir(parents=True, exist_ok=True)
	for name in ["version.txt"] + names:
		target = out / name
		if target.exists() and name != "version.txt":
			print("have", name)
			continue
		print("fetch", name)
		data = archive.read("templates/" + name)
		target.write_bytes(data)
		if not name.endswith((".zip", ".txt", ".apk")):
			target.chmod(0o755)
	print("templates in", out)


if __name__ == "__main__":
	main(sys.argv[1:])
