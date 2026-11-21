extends Node3D
class_name KayKitPlayerVisual

const CHARACTER_SCENES: Array[String] = [
    "res://Assets/KayKit/Adventurers/Characters/gltf/Knight.glb",
    "res://Assets/KayKit/Adventurers/Characters/gltf/Barbarian.glb",
    "res://Assets/KayKit/Adventurers/Characters/gltf/Mage.glb",
    "res://Assets/KayKit/Adventurers/Characters/gltf/Ranger.glb",
    "res://Assets/KayKit/Adventurers/Characters/gltf/Rogue.glb",
    "res://Assets/KayKit/Adventurers/Characters/gltf/Rogue_Hooded.glb",
]
const ANIMATION_SCENES: Array[String] = [
    "res://Assets/KayKit/CharacterAnimations/Rig_Medium/Rig_Medium_General.glb",
    "res://Assets/KayKit/CharacterAnimations/Rig_Medium/Rig_Medium_MovementBasic.glb",
    "res://Assets/KayKit/CharacterAnimations/Rig_Medium/Rig_Medium_MovementAdvanced.glb",
    "res://Assets/KayKit/CharacterAnimations/Rig_Medium/Rig_Medium_CombatMelee.glb",
    "res://Assets/KayKit/CharacterAnimations/Rig_Medium/Rig_Medium_CombatRanged.glb",
    "res://Assets/KayKit/CharacterAnimations/Rig_Medium/Rig_Medium_Simulation.glb",
    "res://Assets/KayKit/CharacterAnimations/Rig_Medium/Rig_Medium_Special.glb",
    "res://Assets/KayKit/CharacterAnimations/Rig_Medium/Rig_Medium_Tools.glb",
]
const CHARACTER_SCALE := 0.78
const WALK_SPEED_THRESHOLD := 0.65
const RUN_SPEED_THRESHOLD := 3.0
static var _shared_animation_library: AnimationLibrary

var _animation_player: AnimationPlayer
var _controlled_player: Node3D
var _previous_position := Vector3.ZERO
var _smoothed_speed := 0.0
var _was_grounded := true
var _action_animation := ""


func _ready() -> void:
    _controlled_player = get_parent() as Node3D
    if _controlled_player == null:
        push_warning("KayKitPlayerVisual precisa ser filho do jogador.")
        return

    var peer_id := int(_controlled_player.get("owner_peer_id"))
    var character_index := posmod(maxi(peer_id - 1, 0), CHARACTER_SCENES.size())
    var character_scene := load(CHARACTER_SCENES[character_index]) as PackedScene
    if character_scene == null:
        push_error("Não foi possível carregar o personagem KayKit selecionado.")
        return

    var model := character_scene.instantiate() as Node3D
    model.name = "KayKitModel"
    model.scale = Vector3.ONE * CHARACTER_SCALE
    add_child(model)

    _animation_player = AnimationPlayer.new()
    _animation_player.name = "KayKitAnimationPlayer"
    _animation_player.root_node = NodePath("../KayKitModel")
    _animation_player.animation_finished.connect(_on_animation_finished)
    add_child(_animation_player)

    var animation_library := _get_shared_animation_library()
    if animation_library != null:
        _animation_player.add_animation_library("", animation_library)
        if _animation_player.has_animation("Idle_A"):
            _animation_player.play("Idle_A")

    _previous_position = _controlled_player.global_position
    _was_grounded = bool(_controlled_player.get("grounded"))
    set_process(true)


func _process(delta: float) -> void:
    if _controlled_player == null or _animation_player == null or delta <= 0.0:
        return

    var current_position := _controlled_player.global_position
    var horizontal_delta := current_position - _previous_position
    horizontal_delta.y = 0.0
    var measured_speed := horizontal_delta.length() / delta
    _previous_position = current_position
    _smoothed_speed = lerpf(_smoothed_speed, measured_speed, clampf(delta * 9.0, 0.0, 1.0))

    if not _action_animation.is_empty() and _animation_player.is_playing():
        if _animation_player.current_animation == _action_animation:
            return
        _action_animation = ""

    var is_grounded := bool(_controlled_player.get("grounded"))
    if not is_grounded:
        if _was_grounded:
            _play_animation("Jump_Full_Short")
        _was_grounded = false
        return

    _was_grounded = true
    var desired_animation := "Idle_A"
    if _smoothed_speed >= WALK_SPEED_THRESHOLD:
        desired_animation = "Running_A" if _smoothed_speed >= RUN_SPEED_THRESHOLD else "Walking_A"

    if _animation_player.current_animation != desired_animation:
        _animation_player.play(desired_animation, 0.18)


func _play_animation(animation_name: String) -> void:
    if _animation_player.has_animation(animation_name):
        _animation_player.play(animation_name, 0.12)


func play_action(animation_name: String) -> void:
    if _animation_player == null or not _animation_player.has_animation(animation_name):
        return
    _action_animation = animation_name
    _animation_player.play(animation_name, 0.12)


func _on_animation_finished(animation_name: StringName) -> void:
    if String(animation_name) == _action_animation:
        _action_animation = ""


func _get_shared_animation_library() -> AnimationLibrary:
    if _shared_animation_library != null:
        return _shared_animation_library

    var library := AnimationLibrary.new()
    var added_count := 0
    for scene_path in ANIMATION_SCENES:
        var animation_scene := load(scene_path) as PackedScene
        if animation_scene == null:
            push_warning("Pacote de animações ausente: " + scene_path)
            continue
        var source_root := animation_scene.instantiate()
        var source_player := source_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
        if source_player != null:
            for animation_name in source_player.get_animation_list():
                if animation_name == "T-Pose" or library.has_animation(animation_name):
                    continue
                library.add_animation(animation_name, source_player.get_animation(animation_name))
                added_count += 1
        source_root.free()

    if added_count == 0:
        push_error("Nenhuma animação KayKit foi carregada.")
        return null

    _shared_animation_library = library
    return _shared_animation_library
