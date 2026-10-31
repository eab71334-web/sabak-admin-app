# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name AModal
extends Control
## Clean in-app dialog: dimmed backdrop, rounded card, title + close button, scrollable body that
## shrinks above the on-screen keyboard.

var content: VBoxContainer
var _margin: MarginContainer
var _panel: PanelContainer
var _scroll: DragScroll
var _top := 18.0
var _bottom := 18.0
var _chrome := 110.0
var _closable := true
var _gone := false


static func open(host: Control, title: String, closable := true) -> AModal:
	var m := AModal.new()
	m._closable = closable
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.z_index = 60
	host.add_child(m)
	m._build(title)
	return m


static func confirm(host: Control, title: String, msg: String, ok_text: String, on_ok: Callable, danger := true) -> void:
	var m := open(host, title, false)
	var tint: Color = AUI.BAD if danger else AUI.ACCENT
	var ic := PanelContainer.new()
	ic.custom_minimum_size = Vector2(64, 64)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ist := AUI.sb(Color(tint.r, tint.g, tint.b, 0.14), 32, Color(tint.r, tint.g, tint.b, 0.55), 2)
	ist.content_margin_left = 0
	ist.content_margin_right = 0
	ist.content_margin_top = 0
	ist.content_margin_bottom = 0
	ic.add_theme_stylebox_override("panel", ist)
	var il := AUI.lbl(ic, "!" if danger else "؟", 34, tint)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	m.content.add_child(ic)
	var ml := AUI.lbl(m.content, msg, 20, AUI.TXT2, true)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	m.content.add_child(row)
	var b1 := AUI.btn(row, "إلغاء", func(): m.close(), AUI.PANEL, 20, 56)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := AUI.btn(row, ok_text, func():
		m.close()
		on_ok.call(), AUI.PANEL, 20, 56)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b2.add_theme_color_override("font_color", tint)
	b2.add_theme_color_override("font_hover_color", tint)
	b2.add_theme_color_override("font_pressed_color", tint)
	for k in ["normal", "hover", "pressed"]:
		var a2 := 0.16 if k == "normal" else (0.24 if k == "hover" else 0.32)
		b2.add_theme_stylebox_override(k, AUI.sb(Color(tint.r, tint.g, tint.b, a2), 28, Color(tint.r, tint.g, tint.b, 0.6), 1))


func close() -> void:
	if _gone:
		return
	_gone = true
	if OS.has_feature("mobile"):
		DisplayServer.virtual_keyboard_hide()
	hide()
	queue_free()


func _build(title: String) -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	var ins := AUI.insets(self)
	_top = 16.0 + ins["top"]
	_bottom = 16.0 + ins["bottom"]
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	if not _closable:
		dim.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
				close())
	add_child(dim)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_theme_constant_override("margin_left", 16)
	_margin.add_theme_constant_override("margin_right", 16)
	add_child(_margin)
	_panel = PanelContainer.new()
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := AUI.sb(Color(0.07, 0.07, 0.08, 0.98), 30, Color(1, 1, 1, 0.14), 1)
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 14
	st.content_margin_bottom = 18
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 24
	_panel.add_theme_stylebox_override("panel", st)
	_margin.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	var t := AUI.lbl(head, title, 26, AUI.TXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not _closable:
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		var x := Button.new()
		x.text = "✕"
		x.flat = true
		x.focus_mode = Control.FOCUS_NONE
		x.custom_minimum_size = Vector2(52, 46)
		x.add_theme_font_size_override("font_size", 24)
		x.add_theme_color_override("font_color", AUI.TXT2)
		x.add_theme_color_override("font_hover_color", AUI.TXT)
		x.add_theme_color_override("font_pressed_color", AUI.ACCENT)
		x.pressed.connect(func(): close())
		head.add_child(x)
	var line := ColorRect.new()
	line.color = AUI.LINE
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)
	_scroll = DragScroll.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	_scroll.add_child(content)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.14)


func _process(_d: float) -> void:
	if _gone or _margin == null or _scroll == null or content == null:
		return
	var win := DisplayServer.window_get_size()
	var kb := float(DisplayServer.virtual_keyboard_get_height()) if OS.has_feature("mobile") else 0.0
	var sy := size.y / maxf(float(win.y), 1.0)
	_margin.add_theme_constant_override("margin_top", int(_top))
	_margin.add_theme_constant_override("margin_bottom", int(_bottom + kb * sy))
	var avail := size.y - _top - _bottom - kb * sy
	var want := content.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(want, 60.0, maxf(120.0, avail - _chrome))


func _unhandled_key_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		close()
