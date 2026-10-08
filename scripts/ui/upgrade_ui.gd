class_name UpgradeUI
extends Control
## 肉鸽升级三选一界面。

signal chosen(upgrade_id: String)

var cards: Array = []


func show_choices(p_cards: Array) -> void:
	cards = p_cards
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()

	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 24)
	cc.add_child(outer)

	var title := Label.new()
	title.text = "选择一项升级"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(900, 260)
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(row)

	for card in cards:
		var b := Button.new()
		b.custom_minimum_size = Vector2(280, 240)
		b.pressed.connect(_on_pick.bind(str(card["id"])))
		row.add_child(b)

		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 12)
		b.add_child(v)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon := Label.new()
		icon.text = str(card.get("icon", "★"))
		icon.add_theme_font_size_override("font_size", 42)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(icon)

		var name_l := Label.new()
		name_l.text = str(card["name"])
		name_l.add_theme_font_size_override("font_size", 22)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(name_l)

		var desc := Label.new()
		desc.text = str(card["desc"])
		desc.add_theme_font_size_override("font_size", 14)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(240, 60)
		desc.modulate = Color(0.75, 0.8, 0.9)
		v.add_child(desc)


func _on_pick(id: String) -> void:
	chosen.emit(id)
