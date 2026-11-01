class_name UnitType
extends Resource
## A kind of regiment (PRD 3.5). Stats are for a full regiment of 100 men;
## HP and attack scale with the men left.

@export var id := ""
@export var display_name := ""
## One or two letters drawn on the army token.
@export var short_name := ""
## Sort order in lists.
@export var order := 0
## "infantry", "ranged", "cavalry" or "siege". Terrain modifiers use this.
@export var unit_class := "infantry"
## Swordsmen and heavy cavalry fight worse in marshes.
@export var heavy := false
@export var hp := 100
@export var attack := 8
@export var defense := 5
## Movement points per turn.
@export var speed := 2
## Shoots in the ranged phase of a battle.
@export var ranged := false
@export var cost_gold := 50
@export var cost_wood := 0
@export var cost_iron := 0
@export var cost_manpower := 100
@export var upkeep_gold := 1
@export var upkeep_food := 1
## Building a province needs before it can recruit this unit; "" for none.
@export var required_building := ""
