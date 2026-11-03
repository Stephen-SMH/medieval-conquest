class_name Troop
extends RefCounted
## The soldiers of one type inside an army (PRD A): how many there are and
## their health. An army (Unit) holds one Troop per soldier type.
##
## `hp` is the troop's health in HP; full health is soldiers × HP per soldier.
## The health bar shows hp ÷ full health. Two kinds of damage (PRD D):
##   - melee (hit) kills: soldiers = ceil(hp ÷ HP per soldier), and a troop with
##     less than a quarter of one soldier's health left is destroyed;
##   - ranged fire (wound) mostly wears health down: a soldier falls only when
##     the troop's health would drop below WOUND_FLOOR, and fire never takes
##     the last soldier, who keeps at least LAST_STAND of his health.

const WOUND_FLOOR := 0.5
const LAST_STAND := 0.5
const DEAD_BELOW := 0.25

var type_id := ""
var soldiers := 0
var hp := 0.0
## Soldiers who have already carried out an order this turn (S&T's "!"): they
## can't be given another until the faction's next turn.
var tired := 0
## Battle multipliers worked out just before a battle: civilization, upgrades.
var attack_mod := 1.0
var defense_mod := 1.0
var charge_mod := 1.0
## Damage taken is divided by this (the Forge's health upgrade).
var toughness := 1.0


func _init(unit_type_id := "", count := 0, health := 1.0) -> void:
	type_id = unit_type_id
	soldiers = maxi(count, 0)
	Rules.ensure_loaded()
	if type_id != "":
		hp = full_hp() * clampf(health, 0.0, 1.0)


func type() -> UnitType:
	return Rules.unit(type_id)


func soldier_hp() -> float:
	return type().soldier_hp()


## Health of these soldiers when unhurt.
func full_hp() -> float:
	return soldiers * soldier_hp()


## Share of full health left: the health bar.
func health() -> float:
	return hp / full_hp() if soldiers > 0 else 0.0


## Fighting weight: HP against a full 20-soldier unit of the type. Attack
## scales with it, so 6 soldiers hit about 6/20 as hard as 20.
func strength() -> float:
	return hp / float(type().hp)


func is_destroyed() -> bool:
	return soldiers <= 0


func power() -> float:
	var unit_type := type()
	return strength() * (unit_type.attack + unit_type.defense) * unit_type.hp / 100.0


## Melee damage: soldiers die as HP runs out.
func hit(damage: float) -> void:
	hp = maxf(hp - damage / toughness, 0.0)
	_settle()


## Ranged damage: wears health down; never takes the last soldier.
func wound(damage: float) -> void:
	if soldiers <= 0:
		return
	hp = maxf(hp - damage / toughness, LAST_STAND * soldier_hp())
	soldiers = mini(soldiers, maxi(1, ceili(hp / (WOUND_FLOOR * soldier_hp()) - 1e-4)))
	hp = minf(hp, full_hp())


## Loses a share of soldiers outright (desertion, starvation, a rout).
func lose_share(share: float) -> void:
	hit(hp * clampf(share, 0.0, 1.0) * toughness)


## Heals towards full health; `share` of the missing health comes back.
func heal(share: float) -> void:
	hp = minf(hp + (full_hp() - hp) * clampf(share, 0.0, 1.0), full_hp())


func _settle() -> void:
	if hp < DEAD_BELOW * soldier_hp():
		soldiers = 0
		hp = 0.0
		tired = 0
		return
	soldiers = mini(soldiers, ceili(hp / soldier_hp() - 1e-4))
	tired = mini(tired, soldiers)
	hp = minf(hp, full_hp())


## Takes `count` soldiers out, with their share of the health. The tired
## go first: a detachment is made of the soldiers just given orders.
func take(count: int) -> Troop:
	count = clampi(count, 0, soldiers)
	var part := Troop.new(type_id, count)
	if count <= 0:
		return part
	part.hp = hp * count / soldiers
	part.tired = mini(tired, count)
	hp -= part.hp
	soldiers -= count
	tired -= part.tired
	return part


## Adds another troop of the same type.
func absorb(other: Troop) -> void:
	soldiers += other.soldiers
	hp += other.hp
	tired = mini(tired + other.tired, soldiers)


func copy() -> Troop:
	var twin := Troop.new(type_id, soldiers)
	twin.hp = hp
	twin.tired = tired
	twin.attack_mod = attack_mod
	twin.defense_mod = defense_mod
	twin.charge_mod = charge_mod
	twin.toughness = toughness
	return twin
