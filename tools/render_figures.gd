extends SceneTree
## Renders the painted unit figures in assets/figures/ from CC0 3D models
## (see CREDITS.md). Each unit type gets two PNGs, rendered at a 3/4 top-down
## angle on a transparent background:
##   <type>.png       the lit, shaded figure
##   <type>_team.png  only the parts that take the faction colour (tunic,
##                    shield face), in grey; the game draws it over the figure
##                    modulated by the faction colour.
##
## The 3D models are not in the repository. Fetch them with
## tools/fetch_figure_models.sh <dir>, then run, with a window (headless
## Godot doesn't render 3D):
##   godot --path . --rendering-method forward_plus -s tools/render_figures.gd -- <dir> [--only=a,b] [--sheet=file.png]
## <dir> holds the Quaternius packs in their own folders: modular_men/,
## single_knight_pack/, animals_pack/ and medieval_weapons_pack/.
## --sheet writes a preview of every figure on one image instead of the PNGs.

const OUT := "res://assets/figures/"
const SIZE := 192  # Output sprite size in pixels.
const SUPERSAMPLE := 3
const VIEW := 3.0  # Metres covered by the sprite, in height and width.
const FEET_Y := 0.80  # Where the feet stand, as a fraction of the sprite height.
const PITCH := 34.0  # Camera elevation in degrees.
const YAW := 28.0  # Camera turn around the figure in degrees.
const TEAM_GREY := Color(0.82, 0.82, 0.82)

## Every unit: the body parts (modular men), recoloured materials, faction
## materials, headgear, weapons and pose. Facing: the figure looks along +Z.
const UNITS := {
	"militia": {"body": "Farmer", "team": ["Farmer_Body:LightBlue"], "colors": {"LightBlue": Color(0.4, 0.3, 0.2)}, "right": ["Axe_Small", 0.62, 0.25], "pose": "raise"},
	"yeoman": {"body": "Farmer", "head": "Adventurer", "team": ["Farmer_Body:LightBlue"], "colors": {"LightBlue": Color(0.4, 0.3, 0.2)}, "right": ["Spear", 2.3, 0.35], "pose": "spear",
		"helmet": ["Helmet1", 1.0]},
	"spearmen": {"body": "King", "head": "Adventurer", "team": ["Blue"], "right": ["Spear", 2.4, 0.35], "pose": "spear",
		"left": ["Shield_Round", 0.62], "helmet": ["Helmet1", 1.0]},
	"sergeant": {"body": "King", "head": "Adventurer", "team": ["Blue"], "right": ["Spear", 2.4, 0.35], "pose": "spear",
		"left": ["Shield_Heater", 0.75], "helmet": ["Helmet2", 1.0], "colors": {"Metal": Color(0.55, 0.56, 0.58)}},
	"swordsmen": {"body": "King", "head": "Adventurer", "team": ["Blue"], "right": ["Sword", 0.95, 0.12], "pose": "sword",
		"left": ["Shield_Heater", 0.75], "helmet": ["Helmet2", 1.0]},
	"huscarl": {"body": "King", "head": "Adventurer", "team": ["Blue"], "right": ["Axe", 1.2, 0.2], "pose": "sword",
		"left": ["Shield_Round_2", 0.7], "helmet": ["Helmet1", 1.0], "colors": {"Hair": Color(0.55, 0.32, 0.12)}},
	"varangian_guard": {"body": "King", "head": "Adventurer", "team": ["Blue"], "right": ["Axe_Double", 1.35, 0.25], "pose": "sword",
		"left": ["Shield_Round", 0.66], "helmet": ["Helmet3", 1.0]},
	"berserker": {"body": "Adventurer", "team": ["LightGreen"], "right": ["Axe_Double", 1.3, 0.25], "pose": "raise",
		"colors": {"Green": Color(0.36, 0.26, 0.16), "Hair": Color(0.62, 0.34, 0.12)}},
	"ghazi": {"body": "Adventurer", "team": ["LightGreen"], "right": ["Sword_2", 0.95, 0.12], "pose": "sword",
		"left": ["Shield_Round", 0.6], "colors": {"Green": Color(0.86, 0.83, 0.74), "Brown": Color(0.8, 0.77, 0.68),
		"Brown2": Color(0.7, 0.67, 0.58)}, "helmet": ["Helmet2", 1.0]},
	"archers": {"body": "Adventurer", "team": ["Green", "LightGreen"], "left": ["Bow_Wooden", 1.1], "pose": "bow"},
	"longbowman": {"body": "Adventurer", "team": ["LightGreen"], "left": ["Bow_Wooden2", 1.55], "pose": "bow",
		"colors": {"Green": Color(0.42, 0.36, 0.24)}},
	"crossbowmen": {"body": "King", "head": "Adventurer", "team": ["Blue"], "pose": "crossbow", "crossbow": true,
		"helmet": ["Helmet1", 1.0]},
	"light_cavalry": {"body": "Adventurer", "team": ["Green", "LightGreen"], "right": ["Spear", 2.4, 0.4], "pose": "rider_spear",
		"horse": "Horse"},
	"heavy_cavalry": {"body": "King", "head": "Adventurer", "team": ["Blue"], "right": ["Spear", 2.8, 0.3], "pose": "rider_lance",
		"left": ["Shield_Heater", 0.7], "helmet": ["Helmet2", 1.0], "horse": "Horse_White"},
	"knight": {"body": "King", "head": "Adventurer", "team": ["Blue"], "right": ["Spear", 2.9, 0.3], "pose": "rider_lance",
		"left": ["Shield_Heater", 0.75], "helmet": ["Helmet3", 1.0], "horse": "Horse_White"},
	"cataphract": {"body": "King", "head": "Adventurer", "team": ["Blue"], "right": ["Spear", 2.8, 0.3], "pose": "rider_lance",
		"helmet": ["Helmet2", 1.0], "horse": "Horse", "horse_colors": {"Main": Color(0.5, 0.52, 0.55), "Main_Light": Color(0.62, 0.64, 0.66),
		"Main_Dark": Color(0.38, 0.39, 0.42)}, "colors": {"Metal": Color(0.62, 0.6, 0.5)}},
	"mamluk": {"body": "Adventurer", "team": ["LightGreen"], "left": ["Bow_Wooden", 1.0], "pose": "rider_bow", "horse": "Horse",
		"colors": {"Green": Color(0.88, 0.85, 0.76), "Brown": Color(0.78, 0.74, 0.64)}, "helmet": ["Helmet2", 1.0]},
	"catapult": {"catapult": true},
}

var models_dir := ""
var viewport: SubViewport
var stage: Node3D
var _cache := {}
var _materials := {}  # MeshInstance3D -> Array of original materials, for the mask pass.


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var only := []
	var sheet := ""
	for arg in args:
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
		elif arg.begins_with("--sheet="):
			sheet = arg.trim_prefix("--sheet=")
		else:
			models_dir = arg
	if models_dir == "" or not DirAccess.dir_exists_absolute(models_dir):
		push_error("Give the folder with the downloaded models: see the top of tools/render_figures.gd")
		quit(1)
		return
	_setup_viewport()
	var images := []
	for id in UNITS:
		if not only.is_empty() and not only.has(id):
			continue
		var pair: Array = await _render_unit(id)
		if sheet == "":
			pair[0].save_png(ProjectSettings.globalize_path(OUT + id + ".png"))
			pair[1].save_png(ProjectSettings.globalize_path(OUT + id + "_team.png"))
			print("rendered ", id)
		images.append(pair)
	if sheet != "":
		_save_sheet(images, sheet)
	quit()


func _setup_viewport() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE) * SUPERSAMPLE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = VIEW
	viewport.add_child(camera)
	# Aim so the ground point (0, 0, 0) lands at FEET_Y down the sprite.
	var direction := Vector3(0, 0, 1).rotated(Vector3.RIGHT, deg_to_rad(-PITCH)).rotated(Vector3.UP, deg_to_rad(YAW))
	var up := Vector3.UP - direction * direction.dot(Vector3.UP)
	var shift := up.normalized() * VIEW * (FEET_Y - 0.5)
	camera.look_at_from_position(direction * 20.0 + shift, shift)
	# A warm key light from the upper left, a cool fill and a rim from behind.
	var key := DirectionalLight3D.new()
	key.light_energy = 1.7
	key.light_color = Color(1.0, 0.95, 0.85)
	key.shadow_enabled = true
	viewport.add_child(key)
	key.look_at_from_position(Vector3(-3, 5, 4), Vector3.ZERO)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.82, 1.0)
	viewport.add_child(fill)
	fill.look_at_from_position(Vector3(4, 1.5, 2), Vector3.ZERO)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.6
	viewport.add_child(rim)
	rim.look_at_from_position(Vector3(1, 3, -5), Vector3.ZERO)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.53, 0.5)
	environment.environment.ambient_light_energy = 1.15
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment.adjustment_enabled = true
	environment.environment.adjustment_saturation = 1.2
	environment.environment.adjustment_contrast = 1.08
	environment.environment.ssao_enabled = true
	environment.environment.ssao_radius = 0.4
	environment.environment.ssao_intensity = 1.5
	viewport.add_child(environment)


# --- Loading -------------------------------------------------------------

func _load(pack: String, model: String) -> Node3D:
	var doc := GLTFDocument.new()
	var gltf := GLTFState.new()
	var path := models_dir.path_join(pack).path_join(model + ".glb")
	if doc.append_from_file(path, gltf) != OK:
		push_error("Can't load " + path)
		return Node3D.new()
	var scene: Node3D = doc.generate_scene(gltf)
	# Runtime glTF loading gives importer nodes; swap them for real mesh instances.
	for importer: ImporterMeshInstance3D in scene.find_children("*", "ImporterMeshInstance3D", true, false):
		var mesh := MeshInstance3D.new()
		mesh.name = importer.name
		mesh.mesh = importer.mesh.get_mesh()
		mesh.skin = importer.skin
		mesh.transform = importer.transform
		var parent := importer.get_parent()
		parent.add_child(mesh)
		mesh.skeleton = mesh.get_path_to(parent) if parent is Skeleton3D else importer.skeleton_path
		importer.free()
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		player.free()
	return scene


func _meshes(node: Node) -> Array:
	return node.find_children("*", "MeshInstance3D", true, false)


func _skeleton(node: Node) -> Skeleton3D:
	var found := node.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null


## The bounding box of a node's meshes in world space.
func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in _meshes(node):
		var b := mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Sets every surface of `node` named in `colors` to a new flat colour.
func _recolor(node: Node, colors: Dictionary) -> void:
	for mesh: MeshInstance3D in _meshes(node):
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i)
			if material and colors.has(material.resource_name):
				var copy: StandardMaterial3D = material.duplicate()
				copy.albedo_color = colors[material.resource_name]
				copy.resource_name = material.resource_name
				mesh.set_surface_override_material(i, copy)


## Marks surfaces whose material is in `names` ("Material" or "Mesh:Material") as the faction's colour.
func _mark_team(node: Node, names: Array) -> void:
	for mesh: MeshInstance3D in _meshes(node):
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i)
			if material and (names.has(material.resource_name) or names.has(mesh.name + ":" + material.resource_name)):
				var copy: StandardMaterial3D = material.duplicate()
				copy.albedo_color = TEAM_GREY
				copy.resource_name = material.resource_name
				copy.set_meta("team", true)
				mesh.set_surface_override_material(i, copy)


func _soften(node: Node) -> void:
	for mesh: MeshInstance3D in _meshes(node):
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i)
			if material is StandardMaterial3D:
				var copy: StandardMaterial3D = material.duplicate()
				copy.resource_name = material.resource_name
				if material.has_meta("team"):
					copy.set_meta("team", true)
				copy.roughness = 0.75
				copy.metallic = 0.35 if material.resource_name.containsn("metal") or material.resource_name.containsn("steel") \
					or material.resource_name.containsn("grey") or material.resource_name == "Armor" else 0.0
				mesh.set_surface_override_material(i, copy)


# --- Characters ----------------------------------------------------------

## Builds a modular man from the body of `body` and the head of `head`, 1.8 m tall, feet on the ground.
func _man(body: String, head: String) -> Node3D:
	var man := _load("modular_men", body)
	stage.add_child(man)
	var skeleton := _skeleton(man)
	for mesh: MeshInstance3D in _meshes(man):
		if mesh.name.ends_with("_Head") and head != body:
			mesh.free()
	if head != body:
		var other := _load("modular_men", head)
		for mesh: MeshInstance3D in _meshes(other):
			if mesh.name.ends_with("_Head"):
				mesh.get_parent().remove_child(mesh)
				skeleton.add_child(mesh)
				mesh.skeleton = mesh.get_path_to(skeleton)
		other.free()
	for mesh: MeshInstance3D in _meshes(man):
		if mesh.name == "Backpack":
			mesh.free()
	var box := _bounds(man)
	man.scale *= 1.8 / box.size.y
	box = _bounds(man)
	man.position.y -= box.position.y
	return man


func _bone_world(skeleton: Skeleton3D, bone: String) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin


## Turns `bone` so it points along `direction` (world space), keeping its children attached.
func _aim(skeleton: Skeleton3D, bone: String, direction: Vector3) -> void:
	var index := skeleton.find_bone(bone)
	var pose := skeleton.get_bone_global_pose(index)
	var to_skeleton := skeleton.global_transform.basis.orthonormalized().inverse()
	var current := pose.basis.y.normalized()
	var target := (to_skeleton * direction).normalized()
	var turned := Basis(Quaternion(current, target)) * pose.basis.orthonormalized()
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	skeleton.set_bone_pose_rotation(index, (parent_basis.inverse() * turned).get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()


## Curls the fingers into a fist so weapons look held.
func _fist(skeleton: Skeleton3D, side: String) -> void:
	for finger in ["Index", "Middle", "Ring", "Pinky"]:
		for joint in [2, 3]:
			var index := skeleton.find_bone("%s%d.%s" % [finger, joint, side])
			if index >= 0:
				skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index) * Quaternion(Vector3.RIGHT, deg_to_rad(70)))
	skeleton.force_update_all_bone_transforms()


func _pose(skeleton: Skeleton3D, pose: String) -> void:
	var arms := {}
	# Right is -X, left is +X, forward is +Z.
	match pose:
		"raise":
			arms = {"UpperArm.R": Vector3(-0.35, 0.1, 0.3), "LowerArm.R": Vector3(-0.1, 1.0, 0.25),
				"UpperArm.L": Vector3(0.25, -1.0, 0.1), "LowerArm.L": Vector3(0.1, -0.6, 0.6)}
		"spear":
			arms = {"UpperArm.R": Vector3(-0.25, -1.0, 0.15), "LowerArm.R": Vector3(-0.05, -0.15, 1.0),
				"UpperArm.L": Vector3(0.3, -1.0, 0.25), "LowerArm.L": Vector3(0.0, -0.3, 1.0)}
		"sword":
			arms = {"UpperArm.R": Vector3(-0.35, -0.6, 0.35), "LowerArm.R": Vector3(-0.1, 0.35, 1.0),
				"UpperArm.L": Vector3(0.3, -1.0, 0.3), "LowerArm.L": Vector3(-0.15, -0.1, 1.0)}
		"bow":
			arms = {"UpperArm.L": Vector3(0.35, 0.12, 1.0), "LowerArm.L": Vector3(0.25, 0.12, 1.0),
				"UpperArm.R": Vector3(-0.75, 0.1, 0.35), "LowerArm.R": Vector3(0.55, 0.15, 0.4)}
		"crossbow":
			arms = {"UpperArm.R": Vector3(-0.3, -0.75, 0.3), "LowerArm.R": Vector3(0.15, 0.1, 1.0),
				"UpperArm.L": Vector3(0.3, -0.7, 0.45), "LowerArm.L": Vector3(-0.1, 0.15, 1.0)}
		"rider_spear":
			arms = {"UpperArm.R": Vector3(-0.3, -1.0, 0.1), "LowerArm.R": Vector3(-0.05, -0.1, 1.0),
				"UpperArm.L": Vector3(0.25, -1.0, 0.3), "LowerArm.L": Vector3(-0.1, -0.2, 1.0)}
		"rider_lance":
			arms = {"UpperArm.R": Vector3(-0.3, -1.0, 0.1), "LowerArm.R": Vector3(-0.05, -0.1, 1.0),
				"UpperArm.L": Vector3(0.3, -1.0, 0.3), "LowerArm.L": Vector3(-0.15, -0.1, 1.0)}
		"rider_bow":
			arms = {"UpperArm.L": Vector3(0.9, 0.12, 0.6), "LowerArm.L": Vector3(0.9, 0.12, 0.5),
				"UpperArm.R": Vector3(-0.3, 0.1, 0.9), "LowerArm.R": Vector3(0.9, 0.1, 0.1)}
	for bone in ["UpperArm.R", "LowerArm.R", "UpperArm.L", "LowerArm.L"]:
		if arms.has(bone):
			_aim(skeleton, bone, arms[bone])
	for bone in ["Hand.R", "Hand.L"]:
		var lower: String = "LowerArm" + bone.substr(4)
		_aim(skeleton, bone, arms.get(lower, Vector3.DOWN))
	if pose.begins_with("rider"):
		_aim(skeleton, "UpperLeg.R", Vector3(-0.45, -0.2, 1.0))
		_aim(skeleton, "UpperLeg.L", Vector3(0.45, -0.2, 1.0))
		_aim(skeleton, "LowerLeg.R", Vector3(-0.15, -1.0, -0.15))
		_aim(skeleton, "LowerLeg.L", Vector3(0.15, -1.0, -0.15))
	else:
		_aim(skeleton, "UpperLeg.R", Vector3(-0.12, -1.0, 0.0))
		_aim(skeleton, "UpperLeg.L", Vector3(0.12, -1.0, 0.08))
		_aim(skeleton, "LowerLeg.R", Vector3(-0.08, -1.0, -0.08))
		_aim(skeleton, "LowerLeg.L", Vector3(0.08, -1.0, 0.0))
	_fist(skeleton, "R")
	_fist(skeleton, "L")


## A prop scaled so its longest side is `length` metres, its long axis on +Y.
func _prop(pack: String, model: String, length: float) -> Node3D:
	var holder := Node3D.new()
	stage.add_child(holder)
	var prop := _load(pack, model)
	holder.add_child(prop)
	var box := _bounds(prop)
	var axis := box.get_longest_axis()
	# Turn the longest axis onto +Y.
	prop.global_basis = Basis(Quaternion(axis.normalized(), Vector3.UP)) * prop.global_basis
	box = _bounds(prop)
	prop.global_basis = prop.global_basis.scaled(Vector3.ONE * (length / box.size.y))
	box = _bounds(prop)
	prop.global_position -= box.get_center()
	return holder


## The hand's grip point.
func _grip(skeleton: Skeleton3D, side: String) -> Vector3:
	return _bone_world(skeleton, "Hand." + side).lerp(_bone_world(skeleton, "Middle2." + side), 0.7)


func _hold(item: Node3D, at: Vector3, up: Vector3, grip: float, length: float, facing := Vector3(0, 0, 1)) -> void:
	item.global_basis = _basis_with_up(up, facing)
	item.global_position = at - up.normalized() * (grip - 0.5) * length


## A basis whose Y is `up` and whose Z leans toward `facing`.
func _basis_with_up(up: Vector3, facing: Vector3) -> Basis:
	var y := up.normalized()
	var x := y.cross(facing).normalized()
	if x.length() < 0.01:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _attach_helmet(skeleton: Skeleton3D, model: String, scale: float) -> void:
	var helmet := _load("single_knight_pack", model)
	stage.add_child(helmet)
	var box := _bounds(helmet)
	var head := _bone_world(skeleton, "Head")
	var neck := _bone_world(skeleton, "Neck")
	var width := 0.3 * scale
	helmet.scale *= width / maxf(box.size.x, box.size.z)
	box = _bounds(helmet)
	var top := head + (head - neck).normalized() * 0.21
	helmet.global_position += top - Vector3(box.get_center().x, box.end.y, box.get_center().z) + Vector3(0, 0.02, 0.0)


func _build_soldier(spec: Dictionary) -> Node3D:
	var man := _man(spec.body, spec.get("head", spec.body))
	var skeleton := _skeleton(man)
	_recolor(man, spec.get("colors", {}))
	_mark_team(man, spec.get("team", []))
	_pose(skeleton, spec.get("pose", "spear"))
	if spec.has("helmet"):
		_attach_helmet(skeleton, spec.helmet[0], spec.helmet[1])
	var pose: String = spec.get("pose", "")
	if spec.has("right"):
		var weapon := _prop("medieval_weapons_pack", spec.right[0], spec.right[1])
		var up := Vector3(0.05, 1, 0.12)
		if pose == "sword":
			up = Vector3(-0.3, 1, 0.75)
		elif pose == "raise":
			up = Vector3(-0.2, 1, -0.15)
		elif pose == "rider_lance":
			up = Vector3(0.05, 0.35, 1)
		_hold(weapon, _grip(skeleton, "R"), up, spec.right[2], spec.right[1], Vector3(1, 0, 0.3))
	if spec.has("left"):
		var item := _prop("medieval_weapons_pack", spec.left[0], spec.left[1])
		if spec.left[0].begins_with("Bow"):
			var up := Vector3(0.0, 1, 0.1) if pose == "bow" else Vector3(0.0, 1, 0.0)
			_hold(item, _grip(skeleton, "L"), up, 0.5, spec.left[1], Vector3(-1, 0, 0.2))
		else:
			# A shield: its face toward +Z and a little outward, on the forearm.
			item.global_basis = Basis()
			var thin := _bounds(item).size
			var face := Vector3(0.35, 0, 1).normalized()
			if thin.x < thin.z:
				item.global_basis = Basis(Vector3.UP, PI / 2)
			item.global_basis = Basis(Vector3.UP, atan2(face.x, face.z)) * item.global_basis
			var arm := _bone_world(skeleton, "LowerArm.L").lerp(_grip(skeleton, "L"), 0.5)
			item.global_position = arm + face * 0.08
		_mark_team(item, ["LightWood"] if spec.left[0].begins_with("Shield") else [])
	if spec.get("crossbow", false):
		_build_crossbow(_grip(skeleton, "R"), _grip(skeleton, "L"))
	return man


func _wood(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	material.resource_name = "Wood"
	return material


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material, basis := Basis()) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = null
	box.material = material
	parent.add_child(mesh)
	mesh.global_basis = basis
	mesh.global_position = at
	return mesh


## A crossbow held level: stock between the hands, a bow across the front.
func _build_crossbow(back: Vector3, front: Vector3) -> void:
	var holder := Node3D.new()
	stage.add_child(holder)
	var forward := Vector3(0.1, 0.05, 1).normalized()
	var start := (back + front) / 2.0 - forward * 0.25
	var basis := Basis.looking_at(-forward, Vector3.UP)
	_box(holder, Vector3(0.05, 0.06, 0.75), start + forward * 0.25, _wood(Color(0.42, 0.27, 0.15)), basis)
	var bow := _prop("medieval_weapons_pack", "Bow_Wooden", 0.7)
	bow.global_basis = _basis_with_up(forward.cross(Vector3.UP), Vector3.UP)
	bow.global_position = start + forward * 0.6


func _build_rider(spec: Dictionary) -> Node3D:
	var horse := _load("animals_pack", spec.horse)
	stage.add_child(horse)
	var box := _bounds(horse)
	horse.scale *= 2.0 / box.size.z if box.size.z > box.size.x else 2.0 / box.size.x
	box = _bounds(horse)
	horse.position.y -= box.position.y
	horse.position.z -= box.get_center().z
	horse.position.x -= box.get_center().x
	_recolor(horse, spec.get("horse_colors", {}))
	var horse_skeleton := _skeleton(horse)
	var man := _build_soldier(spec)
	var skeleton := _skeleton(man)
	var saddle := _bone_world(horse_skeleton, "Torso").lerp(_bone_world(horse_skeleton, "Back"), 0.4)
	var hips := _bone_world(skeleton, "Hips")
	var shift := saddle + Vector3(0, 0.22, -0.05) - hips
	for node in stage.get_children():
		if node != horse:
			node.global_position += shift
	return man


func _build_catapult() -> Node3D:
	var holder := Node3D.new()
	stage.add_child(holder)
	var wood := _wood(Color(0.5, 0.33, 0.18))
	var dark := _wood(Color(0.33, 0.21, 0.11))
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.35, 0.35, 0.37)
	iron.metallic = 0.5
	iron.roughness = 0.5
	iron.resource_name = "Iron"
	# Base frame on four wheels.
	for x in [-0.42, 0.42]:
		_box(holder, Vector3(0.12, 0.12, 1.9), Vector3(x, 0.32, 0), wood)
	for z in [-0.8, 0.0, 0.8]:
		_box(holder, Vector3(0.96, 0.1, 0.1), Vector3(0, 0.36, z), wood)
	for x in [-0.52, 0.52]:
		for z in [-0.6, 0.6]:
			var wheel := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.26
			cylinder.bottom_radius = 0.26
			cylinder.height = 0.08
			cylinder.radial_segments = 14
			cylinder.material = dark
			wheel.mesh = cylinder
			holder.add_child(wheel)
			wheel.rotation = Vector3(0, 0, PI / 2)
			wheel.position = Vector3(x, 0.26, z)
			var hub := _box(holder, Vector3(0.1, 0.1, 0.1), Vector3(x * 1.08, 0.26, z), iron)
			hub.name = "Hub"
	# Uprights and the crossbar the arm swings on.
	for x in [-0.38, 0.38]:
		_box(holder, Vector3(0.1, 0.9, 0.1), Vector3(x, 0.8, -0.1), wood, Basis(Vector3.RIGHT, deg_to_rad(-12)))
		_box(holder, Vector3(0.08, 0.75, 0.08), Vector3(x, 0.7, 0.3), wood, Basis(Vector3.RIGHT, deg_to_rad(35)))
	_box(holder, Vector3(0.9, 0.12, 0.12), Vector3(0, 1.2, -0.18), dark)
	# The throwing arm, cocked back, with a bucket and a stone.
	var arm_dir := Vector3(0, 0.45, -1).normalized()
	var arm_basis := Basis.looking_at(-arm_dir, Vector3.UP)
	_box(holder, Vector3(0.1, 0.1, 1.5), Vector3(0, 0.95, 0.15) + arm_dir * 0.25, dark, arm_basis)
	var bucket_at := Vector3(0, 0.95, 0.15) + arm_dir * 0.95
	_box(holder, Vector3(0.3, 0.12, 0.3), bucket_at + Vector3(0, 0.06, 0), wood, arm_basis)
	var stone := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	var stone_material := _wood(Color(0.55, 0.53, 0.5))
	stone_material.resource_name = "Stone"
	sphere.material = stone_material
	stone.mesh = sphere
	holder.add_child(stone)
	stone.global_position = bucket_at + Vector3(0, 0.2, 0)
	# Counterweight box hanging at the front.
	_box(holder, Vector3(0.36, 0.3, 0.3), Vector3(0, 0.75, 0.62), iron)
	# A faction pennant on the frame.
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = TEAM_GREY
	cloth.resource_name = "Pennant"
	cloth.set_meta("team", true)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box(holder, Vector3(0.035, 1.25, 0.035), Vector3(0.48, 0.95, -0.85), dark)
	_box(holder, Vector3(0.02, 0.24, 0.42), Vector3(0.48, 1.42, -0.63), cloth)
	holder.rotation.y = deg_to_rad(-25)
	holder.scale = Vector3.ONE * 1.05
	return holder


# --- Rendering -----------------------------------------------------------

func _render_unit(id: String) -> Array:
	stage = Node3D.new()
	viewport.add_child(stage)
	var spec: Dictionary = UNITS[id]
	if spec.get("catapult", false):
		_build_catapult()
	elif spec.has("horse"):
		_build_rider(spec)
	else:
		_build_soldier(spec)
	_soften(stage)
	# Every figure looks a little to the viewer's left.
	stage.rotation.y = deg_to_rad(-18 if not spec.has("horse") else -62)
	var color := await _capture()
	_mask_pass(stage)
	var mask := await _capture()
	stage.queue_free()
	await process_frame
	return _team_layer(color, mask)


func _capture() -> Image:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


## Replaces every material with flat black, or flat white for faction-coloured parts.
func _mask_pass(node: Node) -> void:
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	var white := black.duplicate()
	white.albedo_color = Color.WHITE
	for mesh: MeshInstance3D in _meshes(node):
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i)
			mesh.set_surface_override_material(i, white if material and material.has_meta("team") else black)


## The faction-coloured parts of `color`, in grey, scaled down to the output size.
func _team_layer(color: Image, mask: Image) -> Array:
	var team := Image.create(color.get_width(), color.get_height(), false, Image.FORMAT_RGBA8)
	for y in color.get_height():
		for x in color.get_width():
			var m := mask.get_pixel(x, y)
			var amount := m.r * m.a
			if amount <= 0.02:
				continue
			var c := color.get_pixel(x, y)
			var grey := clampf(c.get_luminance() / TEAM_GREY.get_luminance() * 0.95, 0.0, 1.0)
			team.set_pixel(x, y, Color(grey, grey, grey, c.a * amount))
	var small_color := color.duplicate()
	small_color.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	team.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return [small_color, team]


func _save_sheet(images: Array, path: String) -> void:
	var columns := 6
	var rows := ceili(images.size() / float(columns))
	var sheet := Image.create(SIZE * columns, SIZE * rows * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#cdb88f"))
	for i in images.size():
		var at := Vector2i(i % columns, (i / columns) * 2) * SIZE
		sheet.blend_rect(images[i][0], Rect2i(0, 0, SIZE, SIZE), at)
		var tinted: Image = images[i][1]
		var both: Image = images[i][0].duplicate()
		# Preview the team layer tinted red over the figure.
		var red := tinted.duplicate()
		for y in red.get_height():
			for x in red.get_width():
				var p: Color = red.get_pixel(x, y)
				red.set_pixel(x, y, Color(p.r * 0.85, p.g * 0.2, p.b * 0.18, p.a))
		both.blend_rect(red, Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
		sheet.blend_rect(both, Rect2i(0, 0, SIZE, SIZE), at + Vector2i(0, SIZE))
	sheet.save_png(path)
