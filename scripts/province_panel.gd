class_name ProvincePanel
extends PanelContainer
## Side panel: details of the selected province, and the legend for the map mode.

@onready var _body: RichTextLabel = $Margin/Content/Body
@onready var _legend_title: Label = $Margin/Content/LegendTitle
@onready var _legend: VBoxContainer = $Margin/Content/Legend


func show_province(map: MapData, id: String) -> void:
	if id == "":
		_body.text = "[font_size=20][b]No province selected[/b][/font_size]\n\n" \
			+ "Click a province to see who owns it, its terrain and its neighbours."
		return

	var province: Dictionary = map.provinces[id]
	var terrain := map.terrain(id)
	var faction: Dictionary = map.factions[province.owner]
	var lines := PackedStringArray()
	lines.append("[font_size=22][b]%s[/b][/font_size]" % province.name)
	var owner_line := "[color=#%s]%s[/color]" % [faction.color.lightened(0.35).to_html(false), faction.name]
	if province.capital:
		owner_line += " (capital)"
	lines.append(owner_line)
	lines.append("")
	lines.append("[b]Terrain:[/b] %s" % terrain.display_name)
	lines.append("[b]Move cost:[/b] %d" % terrain.move_cost)
	lines.append("[b]Population:[/b] %s" % thousands(province.population))
	lines.append("[b]Food:[/b] +%d per turn" % food_output(map, id))
	lines.append("[b]In battle:[/b] %s" % terrain.battle_text)
	lines.append("")
	lines.append("[b]Neighbours[/b] (move cost from here)")
	for neighbour_id in map.neighbours(id):
		var line := "•  %s — %d" % [map.provinces[neighbour_id].name, map.move_cost(id, neighbour_id)]
		var border := map.border_type(id, neighbour_id)
		if border != "":
			line += " (%s)" % border
		lines.append(line)
	_body.text = "\n".join(lines)


## Shows the legend; `entries` is a list of [Color, String] pairs.
func show_legend(title: String, entries: Array) -> void:
	_legend_title.text = title
	for child in _legend.get_children():
		child.queue_free()
	for entry in entries:
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = entry[0]
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var label := Label.new()
		label.text = entry[1]
		row.add_child(swatch)
		row.add_child(label)
		_legend.add_child(row)


## Food a province grows per turn before season and buildings.
static func food_output(map: MapData, id: String) -> int:
	return roundi(map.terrain(id).food_output * map.provinces[id].population / 10000.0)


static func thousands(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result
