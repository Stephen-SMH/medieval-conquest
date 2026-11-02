class_name Unit
extends RefCounted
## An army on the map (PRD A): an owner, a region and a composition of
## soldier types, one Troop per type, e.g. 8 militia + 2 archers. A region
## holds one army. The class keeps its old name, Unit, because every part of
## the game says "unit" for the token on the map.
##
## `type_id` and `type()` give the army's dominant type (most soldiers), which
## picks its icon where only one is shown. There are no generals or ranks:
## troops only get stronger through the Forge's upgrades.

## Most soldiers one region's army may hold (PRD A: raised from 20 to 30 so a
## mixed army has room for several types).
const CAP := 30

var id := 0
var owner := ""
var province := ""
## One per soldier type, in the types' display order.
var troops: Array[Troop] = []
var move_points_left := 0
## Set when the army attacked or fought this turn.
var attacked := false
## Set when the army moved this turn.
var moved := false

## The dominant soldier type.
var type_id: String:
	get:
		var best: Troop = null
		for troop in troops:
			if best == null or troop.soldiers > best.soldiers:
				best = troop
		return best.type_id if best != null else ""

## Health in HP, summed over the troops.
var hp: float:
	get:
		var total := 0.0
		for troop in troops:
			total += troop.hp
		return total


func _init(unit_type_id := "", unit_owner := "", region := "", soldiers := UnitType.SOLDIERS) -> void:
	owner = unit_owner
	province = region
	if unit_type_id != "":
		add(unit_type_id, soldiers)


func type() -> UnitType:
	return Rules.unit(type_id) if not troops.is_empty() else null


func troop(troop_type: String) -> Troop:
	for entry in troops:
		if entry.type_id == troop_type:
			return entry
	return null


## Adds soldiers of a type at full health (or `health`), joining the troop
## already there.
func add(troop_type: String, count: int, health := 1.0) -> void:
	if count <= 0:
		return
	add_troop(Troop.new(troop_type, count, health))


func add_troop(incoming: Troop) -> void:
	if incoming.soldiers <= 0:
		return
	var existing := troop(incoming.type_id)
	if existing != null:
		existing.absorb(incoming)
		return
	troops.append(incoming)
	troops.sort_custom(func(a: Troop, b: Troop): return a.type().order < b.type().order)


func soldiers() -> int:
	var total := 0
	for entry in troops:
		total += entry.soldiers
	return total


## {type id: soldiers}, in display order.
func composition() -> Dictionary:
	var result := {}
	for entry in troops:
		if entry.soldiers > 0:
			result[entry.type_id] = entry.soldiers
	return result


func type_count() -> int:
	return composition().size()


## Health when unhurt.
func full_hp() -> float:
	var total := 0.0
	for entry in troops:
		total += entry.full_hp()
	return total


func max_hp() -> float:
	return full_hp()


## The health bar: 1 when unhurt.
func health() -> float:
	var full := full_hp()
	return hp / full if full > 0.0 else 0.0


func strength() -> float:
	return health()


func is_destroyed() -> bool:
	return soldiers() <= 0


## Drops troops with no soldiers left.
func cleanup() -> void:
	troops.assign(troops.filter(func(t: Troop): return t.soldiers > 0))


## Rough fighting strength, used to decide who fights first.
func power() -> float:
	var total := 0.0
	for entry in troops:
		total += entry.power()
	return total


## For a single-type army: sets its soldiers at full health.
func set_soldiers(count: int) -> void:
	if troops.is_empty():
		return
	var only := troops[0]
	troops.assign([only])
	only.soldiers = maxi(count, 0)
	only.hp = only.full_hp()


func all_cavalry() -> bool:
	return not troops.is_empty() and troops.all(func(t: Troop): return t.type().is_cavalry())


func all_ranged() -> bool:
	return not troops.is_empty() and troops.all(func(t: Troop): return t.type().is_ranged())


func has_melee() -> bool:
	return troops.any(func(t: Troop): return not t.type().is_ranged() and t.soldiers > 0)


## Longest reach of its ranged troops, 0 if it has none.
func max_range() -> int:
	var reach := 0
	for entry in troops:
		reach = maxi(reach, entry.type().attack_range)
	return reach


## Splits off `wanted` ({type: soldiers}) into a new army in the same place,
## each type taking its share of health. The new army has id 0: GameState gives ids.
func split(wanted: Dictionary) -> Unit:
	var part := Unit.new("", owner, province)
	for troop_type in wanted:
		var source := troop(troop_type)
		if source != null:
			part.add_troop(source.take(int(wanted[troop_type])))
	cleanup()
	return part


## Takes in another army's troops.
func absorb(other: Unit) -> void:
	for entry in other.troops:
		add_troop(entry)
	other.troops.clear()


func reset_turn() -> void:
	move_points_left = 2 if all_cavalry() else 1
	attacked = false
	moved = false


## A copy for forecasts.
func copy() -> Unit:
	var twin := Unit.new("", owner, province)
	twin.id = id
	for entry in troops:
		twin.troops.append(entry.copy())
	return twin


## "8 militia, 2 archers".
func describe() -> String:
	var parts := PackedStringArray()
	for entry in troops:
		parts.append("%d %s" % [entry.soldiers, entry.type().display_name.to_lower()])
	return ", ".join(parts)
