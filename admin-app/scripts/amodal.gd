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


static func open(host: Control, title: String) -> AModal:
	var m := AModal.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.z_index = 60
	host.add_child(m)
	m._build(title)
	return m


static func confirm(host: Control, title: String, msg: String, ok_text: String, on_ok: Callable, danger := true) -> void:
	var m := open(host, title)
	AUI.lbl(m.content, msg, 21, AUI.TXT2, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	m.content.add_child(row)
	var b1 := AUI.btn(row, "إلغاء", func(): m.close(), AUI.CARD, 20, 56)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := AUI.btn(row, ok_text, func():
		m.close()
		on_ok.call(), AUI.DANGER if danger else AUI.ACCENT, 20, 56)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func close() -> void:
	if OS.has_feature("mobile"):
		DisplayServer.virtual_keyboard_hide()
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
	var x := AUI.btn(head, "✕", func(): close(), AUI.CARD, 20, 46)
	x.custom_minimum_size = Vector2(46, 46)
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
	if _margin == null:
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
