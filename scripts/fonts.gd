extends Node
## Autoload "Fonts": gives the game fonts symbol fallbacks. Cinzel and IM Fell
## English have no ★ ☆ ✓ ✗ ■ → −. Desktop and Android borrow those from a system
## font, but a web build has none, so they come from the Noto fonts made by
## tools/make_symbol_fonts.sh. (Fallbacks set in the fonts' import settings are
## lost on export, so they are set here.)

const GAME_FONTS := [
	"res://assets/fonts/Cinzel.ttf",
	"res://assets/fonts/IMFellEnglish-Regular.ttf",
	"res://assets/fonts/IMFellEnglish-Italic.ttf",
]
const SYMBOL_FONTS := [
	"res://assets/fonts/NotoSansSymbols2-Symbols.ttf",
	"res://assets/fonts/NotoSansMath-Arrows.ttf",
]


func _init() -> void:
	var symbols: Array[Font] = []
	for path in SYMBOL_FONTS:
		symbols.append(load(path))
	# The theme holds these fonts, so this is the same object every label draws with.
	for path in GAME_FONTS:
		var font: FontFile = load(path)
		font.fallbacks = symbols
