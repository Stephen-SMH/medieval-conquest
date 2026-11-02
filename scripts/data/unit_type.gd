class_name UnitType
extends Resource
## A kind of unit (PRD 3.5, 8.2, 8.5). A unit has up to 20 soldiers; `hp` and
## `attack` are for a full unit, and both scale with the soldiers left.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
## Sort order in lists.
@export var order := 0
## "infantry", "ranged", "cavalry" or "siege". Picks the token icon and terrain modifiers.
@export var unit_class := "infantry"
## Swordsmen and heavy cavalry fight worse in marshes.
@export var heavy := false
## HP of a full unit of 20 soldiers.
@export var hp := 100
@export var attack := 8
@export var defense := 5
## Move points per turn (UT-4).
@export var move_points := 1
## 0 for melee; ranged units shoot at regions this many steps away (OR-4).
@export var attack_range := 0
## The base unit whose row and column of the counter table this unit uses.
@export var counter_as := ""
## Extra attack in the charge phase (knights).
@export var charge_bonus := 1.0
## Attack rises as HP falls and the unit never routs (berserkers).
@export var berserker := false
## Can move and shoot in the same turn, in either order (horse archers).
@export var skirmisher := false
## "" for the base roster, else the only civilization that can recruit it.
@export var civilization := ""
## Price in gold (8.9: gold is the only resource).
@export var cost_gold := 50
## Gold a full unit costs each turn.
@export var upkeep_gold := 1


const SOLDIERS := 20


## The name for several soldiers: "Longbowmen", "Knights"; plural names stay.
func plural_name() -> String:
	if display_name.ends_with("man"):
		return display_name.left(-3) + "men"
	if display_name.ends_with("s") or display_name.ends_with("men") or display_name.ends_with("cavalry") or display_name == "Militia":
		return display_name
	return display_name + "s"


func soldier_hp() -> float:
	return float(hp) / SOLDIERS


func is_ranged() -> bool:
	return attack_range > 0


func is_cavalry() -> bool:
	return unit_class == "cavalry"


## The counter-table id this unit fights as.
func counter_id() -> String:
	return counter_as if counter_as != "" else id
