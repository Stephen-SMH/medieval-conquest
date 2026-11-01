class_name ResourceBar
extends HBoxContainer
## The player's stockpile with each resource's change this turn (PRD RS-2).
## Hovering a resource shows where the change comes from (RS-3).

signal tax_changed(level: String)

const NAMES := {"gold": "Gold", "food": "Food", "wood": "Wood", "iron": "Iron", "manpower": "Men"}

var _labels := {}
var _tax: OptionButton


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	for resource in FactionState.RESOURCES:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.add_theme_font_size_override("font_size", 15)
		add_child(label)
		_labels[resource] = label
	var tax_label := Label.new()
	tax_label.text = "Tax:"
	add_child(tax_label)
	_tax = OptionButton.new()
	_tax.focus_mode = Control.FOCUS_NONE
	for level in FactionState.TAX_LEVELS:
		_tax.add_item(level.capitalize())
	_tax.tooltip_text = "Low: −40% taxes, +15 happiness.\nHigh: +50% taxes, −20 happiness."
	_tax.item_selected.connect(func(index): tax_changed.emit(FactionState.TAX_LEVELS[index]))
	add_child(_tax)


func show_faction(state: GameState, faction_id: String) -> void:
	var faction: FactionState = state.factions[faction_id]
	var lines := Economy.breakdown(state, faction_id)
	var caps := {"food": Economy.food_cap(state, faction_id), "wood": Economy.material_cap(state, faction_id),
		"iron": Economy.material_cap(state, faction_id)}
	for resource in FactionState.RESOURCES:
		var change := 0.0
		var tooltip := PackedStringArray()
		for line in lines[resource]:
			change += line[1]
			tooltip.append("%s: %+d" % [line[0], roundi(line[1])])
		if tooltip.is_empty():
			tooltip.append("No change this turn")
		var amount := roundi(faction.resources[resource])
		var text := "%s %d" % [NAMES[resource], amount]
		if caps.has(resource):
			text += "/%d" % roundi(caps[resource])
			tooltip.append("Storage: %d (anything above is lost at the end of the turn)" % roundi(caps[resource]))
		var label: Label = _labels[resource]
		label.text = "%s (%+d)" % [text, roundi(change)]
		label.tooltip_text = "\n".join(tooltip)
		label.add_theme_color_override("font_color", Color("#f08070") if change < 0 else Color("#e8e4dc"))
	_tax.select(FactionState.TAX_LEVELS.find(faction.tax))
