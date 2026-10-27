# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name AUI
extends RefCounted
## Small UI helpers for the admin app.

const BG := Color(0.04, 0.045, 0.06)
const PANEL := Color(0.085, 0.092, 0.118)
const CARD := Color(0.11, 0.118, 0.15)
const LINE := Color(1, 1, 1, 0.09)
const TXT := Color(0.94, 0.95, 0.97)
const TXT2 := Color(0.62, 0.66, 0.74)
const ACCENT := Color(1.0, 0.47, 0.1)
const OK := Color(0.4, 0.85, 0.5)
const BAD := Color(1.0, 0.4, 0.38)
const GOLD := Color(1.0, 0.8, 0.25)


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
	var fg := Color.BLACK if col == ACCENT else TXT
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", TXT2)
	b.add_theme_stylebox_override("normal", sb(col, 10))
	b.add_theme_stylebox_override("hover", sb(col.lightened(0.08), 10))
	b.add_theme_stylebox_override("pressed", sb(col.lightened(0.16), 10))
	b.add_theme_stylebox_override("disabled", sb(col.darkened(0.35), 10))
	b.pressed.connect(cb)
	if parent:
		parent.add_child(b)
	return b


static func card(parent: Node, col := CARD) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(col, 14, LINE, 1))
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
	le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER if numeric else LineEdit.KEYBOARD_TYPE_DEFAULT
	v.add_child(le)
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
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	return v
