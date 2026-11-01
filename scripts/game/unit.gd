class_name Unit
extends RefCounted
## One unit token on the map (PRD 8.2): a type, an owner, a region, HP for up
## to 20 soldiers, experience and rank, and an optional general.

const RANK_NAMES := ["Recruit", "Veteran", "Elite", "Hero"]
const RANK_BONUS := [0.0, 0.10, 0.20, 0.30]  # Attack and defense (UT-6).
const RANK_XP := [0, 2, 5, 9]  # Experience needed for each rank.
## A unit with less than this share of its HP left is destroyed.
const DESTROYED_BELOW := 0.05

var id := 0
var type_id := ""
var owner := ""
var province := ""
var hp := 0.0
var xp := 0
var general: General
var move_points_left := 0
## Set when the unit attacked or fought this turn. It can then only retreat (OR-5).
var attacked := false
## Set when the unit moved this turn.
var moved := false

## Battle multipliers worked out by GameState just before a battle: rank,
## general, civilization, walls and research.
var attack_mod := 1.0
var defense_mod := 1.0
var charge_mod := 1.0


func _init(unit_type_id := "", unit_owner := "", region := "") -> void:
	type_id = unit_type_id
	owner = unit_owner
	province = region
	if type_id != "":
		hp = type().hp


func type() -> UnitType:
	return Rules.unit(type_id)


func max_hp() -> float:
	return float(type().hp)


func strength() -> float:
	return hp / max_hp()


## Soldiers left (UT-1): ceil(HP ÷ HP per soldier).
func soldiers() -> int:
	return ceili(hp / type().soldier_hp() - 0.0001)


func set_soldiers(count: int) -> void:
	hp = clampf(count * type().soldier_hp(), 0.0, max_hp())


func is_destroyed() -> bool:
	return strength() < DESTROYED_BELOW


func rank() -> int:
	var result := 0
	for i in RANK_XP.size():
		if xp >= RANK_XP[i]:
			result = i
	return result


func rank_name() -> String:
	return RANK_NAMES[rank()]


func reset_turn() -> void:
	move_points_left = type().move_points
	attacked = false
	moved = false


## Lets the unit keep the battle flags and modifiers; used for forecasts.
func copy() -> Unit:
	var twin := Unit.new(type_id, owner, province)
	twin.id = id
	twin.hp = hp
	twin.xp = xp
	twin.general = general
	twin.attack_mod = attack_mod
	twin.defense_mod = defense_mod
	twin.charge_mod = charge_mod
	return twin
