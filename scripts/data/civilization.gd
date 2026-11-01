class_name Civilization
extends Resource
## A playable civilization (PRD 8.5): its special units and national bonus.

@export var id := ""
@export var display_name := ""
## Name used for a faction of this civilization in skirmish.
@export var faction_name := ""
@export var color := Color.WHITE
@export var order := 0
@export_multiline var description := ""
@export_multiline var bonus_text := ""
@export var special_units: Array[String] = []
## Campaigns you must finish before it can be played: 0 means open from the start.
@export var unlock_after_campaigns := 0
