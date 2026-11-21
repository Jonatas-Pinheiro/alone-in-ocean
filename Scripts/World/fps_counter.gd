extends CanvasLayer

var label: Label

func _ready() -> void:
	# Cria o Label dinamicamente na tela
	label = Label.new()
	label.position = Vector2(16, 16)
	add_child(label)
	
	# Deixa a fonte legível (opcional)
	label.add_theme_font_size_override("font_size", 18)

func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	label.text = "FPS: %d" % fps
	
	# Alerta visual: muda a cor se o desempenho cair
	if fps < 30:
		label.add_theme_color_override("font_color", Color.RED)      # Crítico
	elif fps < 50:
		label.add_theme_color_override("font_color", Color.YELLOW)   # Atenção
	else:
		label.add_theme_color_override("font_color", Color.GREEN)    # Fluido
