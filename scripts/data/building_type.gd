class_name BuildingType
extends Resource
## A building a province can construct (PRD 3.11). Bonuses are per level.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var order := 0
@export var cost_gold := 100
@export var build_turns := 1
@export var max_level := 1
## Cost multiplier for each level (level 1 first); empty for the same cost every level.
@export var level_cost_multipliers: Array[float] = []
## Terrains it can be built on; empty for any terrain.
@export var allowed_terrains: Array[String] = []
## Extra gold a turn, per level.
@export var gold := 0
