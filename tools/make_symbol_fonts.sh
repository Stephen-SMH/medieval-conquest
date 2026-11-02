#!/bin/sh
# Make the symbol fallback fonts in assets/fonts/ from Noto (SIL OFL 1.1).
#
# Cinzel and IM Fell English have no ★ ☆ ✓ ✗ ■ → −. On desktop and Android Godot
# borrows them from a system font, but a web build has none, so the game fonts
# fall back to these (set as "fallbacks" in their .import files). Each is cut
# down to the symbol blocks with fontTools (pip install fonttools).
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
base=https://github.com/google/fonts/raw/main/ofl
curl -sSL -o "$tmp/symbols.ttf" "$base/notosanssymbols2/NotoSansSymbols2-Regular.ttf"
curl -sSL -o "$tmp/math.ttf" "$base/notosansmath/NotoSansMath-Regular.ttf"
curl -sSL -o assets/fonts/NotoSansSymbols2-OFL.txt "$base/notosanssymbols2/OFL.txt"
curl -sSL -o assets/fonts/NotoSansMath-OFL.txt "$base/notosansmath/OFL.txt"
# Arrows, maths operators, technical, geometric shapes, miscellaneous symbols, dingbats.
fonttools subset "$tmp/symbols.ttf" --unicodes="U+2190-23FF,U+25A0-27BF" \
	--layout-features='*' --output-file=assets/fonts/NotoSansSymbols2-Symbols.ttf
# Only the arrows and the minus sign, which Symbols 2 lacks or lacks some of.
fonttools subset "$tmp/math.ttf" --unicodes="U+2190-21FF,U+2212" \
	--layout-features='*' --output-file=assets/fonts/NotoSansMath-Arrows.ttf
rm -r "$tmp"
# Godot makes a line as tall as the tallest of a font and its fallbacks, so give
# these the line height of IM Fell English (0.905/0.363 em) or less; otherwise
# every label in the game grows.
python3 - <<'PY'
from fontTools.ttLib import TTFont
for name in ["NotoSansSymbols2-Symbols", "NotoSansMath-Arrows"]:
	path = "assets/fonts/%s.ttf" % name
	font = TTFont(path)
	em = font["head"].unitsPerEm
	ascent, descent = round(0.90 * em), round(0.36 * em)
	font["hhea"].ascent, font["hhea"].descent, font["hhea"].lineGap = ascent, -descent, 0
	os2 = font["OS/2"]
	os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = ascent, -descent, 0
	os2.usWinAscent, os2.usWinDescent = ascent, descent
	font.save(path)
PY
ls -la assets/fonts/Noto*
