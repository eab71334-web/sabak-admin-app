# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name AUI
extends RefCounted
## Small UI helpers for the admin app.

const BG := Color(0.0, 0.0, 0.0)
const PANEL := Color(0.06, 0.06, 0.07)
const CARD := Color(1, 1, 1, 0.06)          # frosted-glass card
const LINE := Color(1, 1, 1, 0.11)
const TXT := Color(0.97, 0.97, 0.98)
const TXT2 := Color(0.62, 0.62, 0.68)
const ACCENT := Color(0.83, 0.68, 0.36)      # the gold of the icon
const OK := Color(0.45, 0.86, 0.62)
const BAD := Color(1.0, 0.43, 0.41)
const GOLD := Color(0.93, 0.78, 0.46)
const DANGER := Color(0.78, 0.2, 0.22)


static func sb(col: Color, radius := 12, border := Color.TRANSPARENT, bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s


static func lbl(parent: Node, text: String, fs := 20, color := TXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if parent:
		parent.add_child(l)
	return l


static func btn(parent: Node, text: String, cb: Callable, col := CARD, fs := 20, h := 54) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", fs)
	var solid := col == ACCENT or col == DANGER
	var base := col
	var edge := Color.TRANSPARENT
	var bw := 0
	if not solid:
		base = Color(1, 1, 1, 0.09) if col == PANEL else col   # glass
		edge = Color(1, 1, 1, 0.12)
		bw = 1
	var fg := Color(0.05, 0.04, 0.02) if col == ACCENT else TXT
	var rad := int(h * 0.5)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", TXT2)
	b.add_theme_stylebox_override("normal", sb(base, rad, edge, bw))
	b.add_theme_stylebox_override("hover", sb(base.lightened(0.1), rad, edge, bw))
	b.add_theme_stylebox_override("pressed", sb(base.lightened(0.2), rad, edge, bw))
	b.add_theme_stylebox_override("disabled", sb(Color(base.r, base.g, base.b, base.a * 0.45), rad, edge, bw))
	b.pressed.connect(cb)
	if parent:
		parent.add_child(b)
	return b


static func card(parent: Node, col := CARD) -> VBoxContainer:
	var p := PanelContainer.new()
	var st := sb(col, 24, LINE, 1)
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 14
	st.content_margin_bottom = 14
	p.add_theme_stylebox_override("panel", st)
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v


static func field(parent: Node, title: String, value := "", numeric := false, hint := "") -> LineEdit:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(v)
	lbl(v, title, 15, TXT2)
	var le := LineEdit.new()
	le.text = value
	le.placeholder_text = hint
	le.custom_minimum_size = Vector2(0, 52)
	le.add_theme_font_size_override("font_size", 20)
	var fn := sb(Color(1, 1, 1, 0.07), 18, LINE, 1)
	var ff := sb(Color(1, 1, 1, 0.09), 18, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.9), 2)
	le.add_theme_stylebox_override("normal", fn)
	le.add_theme_stylebox_override("focus", ff)
	le.add_theme_stylebox_override("read_only", fn)
	le.add_theme_color_override("font_color", TXT)
	le.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.28))
	le.add_theme_color_override("caret_color", ACCENT)
	le.add_theme_color_override("selection_color", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35))
	le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER if numeric else LineEdit.KEYBOARD_TYPE_DEFAULT
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(le)
	# iOS has no paste menu inside game text fields, so give an explicit button.
	var pb := btn(row, "لصق", func():
		var clip := DisplayServer.clipboard_get().strip_edges()
		if clip != "":
			le.text = clip
			le.caret_column = clip.length()
			le.text_changed.emit(clip), CARD, 17, 52)
	pb.custom_minimum_size = Vector2(84, 52)
	# the iOS number pad has no Return key and covers the dialog buttons: give a "done" button that closes the keyboard
	var db := btn(row, "تم", func():
		le.release_focus()
		AUI.hide_kb(), ACCENT, 17, 52)
	db.custom_minimum_size = Vector2(70, 52)
	db.visible = false
	le.focus_entered.connect(func(): db.visible = true)
	le.focus_exited.connect(func(): db.visible = false)
	le.text_submitted.connect(func(_t: String):
		le.release_focus()
		AUI.hide_kb())
	return le


static func when(ts: int) -> String:
	if ts <= 0:
		return "-"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(ts + bias)
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


static func usd(v: float) -> String:
	return "$%.2f" % v


static func scroll_page(parent: Node) -> VBoxContainer:
	var sc := DragScroll.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	return v


## Space taken by the notch / status bar (top) and the home indicator (bottom), in UI pixels.
static func insets(node: Node) -> Dictionary:
	var win := Vector2(DisplayServer.window_get_size())
	var sa := Rect2(DisplayServer.get_display_safe_area())
	if win.y <= 0.0 or sa.size.y <= 0.0:
		return {"top": 0.0, "bottom": 0.0}
	var sy: float = node.get_viewport().get_visible_rect().size.y / win.y
	return {"top": maxf(sa.position.y, 0.0) * sy, "bottom": maxf(win.y - sa.end.y, 0.0) * sy}


static func hide_kb() -> void:
	if OS.has_feature("mobile"):
		DisplayServer.virtual_keyboard_hide()
