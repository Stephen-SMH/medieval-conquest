class_name TerrainType
extends Resource
## A kind of land (PRD 3.1): how hard it is to cross
## and how it changes battles fought on it.

@export var id := ""
@export var display_name := ""
@export var color := Color.WHITE
@export var move_cost := 1
## Short text for the province panel.
@export_multiline var battle_text := ""
## Attack multiplier per unit class ("infantry", "ranged", "cavalry", "siege"), for both sides.
@export var attack_mods := {}
## Extra attack multiplier for heavy units (swordsmen, heavy cavalry) on top of attack_mods.
@export var heavy_mod := 1.0
## Attack multiplier for every regiment of the defending army.
@export var defender_mod := 1.0
## Attack multiplier for every regiment of the attacking army.
@export var attacker_mod := 1.0
## Extra attack multiplier for defending regiments, per unit class.
@export var defending_class_mods := {}
