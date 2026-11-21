extends CanvasLayer

var label: Label
var _refresh_elapsed := 0.0
var _last_status := -1
const REFRESH_INTERVAL := 0.25

func _ready() -> void:
	# Cria o Label dinamicamente na tela
	label = Label.new()
	label.position = Vector2(16, 16)
	add_child(label)
	
	# Deixa a fonte legível (opcional)
	label.add_theme_font_size_override("font_size", 18)

func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL:
		return
	_refresh_elapsed = fposmod(_refresh_elapsed, REFRESH_INTERVAL)

	var fps := Engine.get_frames_per_second()
	label.text = "FPS: %d" % fps
	var status := 0 if fps < 30 else (1 if fps < 50 else 2)
	if status == _last_status:
		return
	_last_status = status
	var color := Color.RED if status == 0 else (Color.YELLOW if status == 1 else Color.GREEN)
	label.add_theme_color_override("font_color", color)
