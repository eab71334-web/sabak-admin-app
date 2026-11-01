# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name ALock
extends Control
## 4-digit PIN lock screen for the admin app.

var _on_ok: Callable
var _dots: Label
var _msg: Label
var _pin := ""


static func hash_pin(p: String) -> String:
	return (p + "sabak-pin").sha256_text()


static func show_lock(host: Control, on_ok: Callable) -> ALock:
	var l := ALock.new()
	l._on_ok = on_ok
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.z_index = 200
	host.add_child(l)
	l._build()
	return l


func _build() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	cc.add_child(v)
	var lg := ALogo.new(90)
	lg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(lg)
	_msg = AUI.lbl(v, "أدخل الرقم السري", 24, AUI.TXT)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dots = AUI.lbl(v, "", 44, AUI.ACCENT)
	_dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paint()
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 14)
	v.add_child(g)
	for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]:
		if k == "":
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(88, 88)
			g.add_child(sp)
			continue
		var b := AUI.btn(g, k, func(): _press(k), AUI.PANEL, 30, 88)
		b.custom_minimum_size = Vector2(88, 88)


func _paint() -> void:
	var s := ""
	for i in 4:
		s += ("●  " if i < _pin.length() else "○  ")
	_dots.text = s.strip_edges()


func _press(k: String) -> void:
	if k == "⌫":
		_pin = _pin.substr(0, maxi(0, _pin.length() - 1))
	elif _pin.length() < 4:
		_pin += k
	_paint()
	if _pin.length() == 4:
		if hash_pin(_pin) == Api.pin_hash:
			queue_free()
			if _on_ok.is_valid():
				_on_ok.call()
		else:
			_pin = ""
			_msg.text = "رقم خاطئ"
			_msg.add_theme_color_override("font_color", AUI.BAD)
			_paint()
