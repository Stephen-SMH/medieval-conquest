class_name Unit
extends RefCounted
## One unit token on the map (PRD 8.2): a type, an owner, a region and HP for
## up to 20 soldiers. There are no generals or ranks: troops only get stronger
## through the Forge's upgrades.

## A unit with less than this share of its HP left is destroyed.
const DESTROYED_BELOW := 0.05

var id := 0
var type_id := ""
var owner := ""
var province := ""
var hp := 0.0
var move_points_left := 0
## Set when the unit attacked or fought this turn. It can then only retreat (OR-5).
var attacked := false
## Set when the unit moved this turn.
var moved := false
## Free moves left this turn between two coastal regions (Norse raiding).
var coastal_moves := 0

## Battle multipliers worked out by GameState just before a battle:
## civilization and upgrades.
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


## Rough fighting strength, used to decide who fights first.
func power() -> float:
	var unit_type := type()
	return strength() * (unit_type.attack + unit_type.defense) * unit_type.hp / 100.0


func reset_turn() -> void:
	move_points_left = type().move_points
	attacked = false
	moved = false


## Lets the unit keep the battle flags and modifiers; used for forecasts.
func copy() -> Unit:
	var twin := Unit.new(type_id, owner, province)
	twin.id = id
	twin.hp = hp
	twin.attack_mod = attack_mod
	twin.defense_mod = defense_mod
	twin.charge_mod = charge_mod
	return twin
