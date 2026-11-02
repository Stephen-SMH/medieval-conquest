class_name TechType
extends Resource
## A technology in one of the two research trees (PRD 8.7).

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
## "economy" or "military".
@export var tree := "economy"
@export var tier := 1
@export var cost_gold := 100
@export var turns := 2
## Techs needed first.
@export var requires: Array[String] = []
## Income multipliers: "gold" (all income) or "market".
@export var income := {}
## Extra gold from every region a turn.
@export var region_bonus := 0
## Extra gold a turn from regions of these terrains: {"hills": 3}.
@export var terrain_income := {}
## Multiplier on unit upkeep.
@export var upkeep := 1.0
## Battle multipliers by unit class ("infantry", "ranged", "cavalry", "siege"; "melee" for all non-ranged).
@export var attack := {}
@export var defense := {}
@export var charge := 1.0
