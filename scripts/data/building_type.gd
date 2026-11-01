class_name BuildingType
extends Resource
## A building a province can construct (PRD 3.11). Bonuses are per level.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var order := 0
@export var cost_gold := 100
@export var cost_wood := 0
@export var cost_iron := 0
@export var build_turns := 1
@export var max_level := 1
## Terrains it can be built on; empty for any terrain.
@export var allowed_terrains: Array[String] = []
@export var food := 0
@export var gold := 0
@export var wood := 0
@export var iron := 0
## Extra food the faction can store (granary).
@export var food_storage := 0
## Change to the province's happiness.
@export var happiness := 0
