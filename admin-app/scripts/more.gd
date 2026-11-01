# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name AMore
extends VBoxContainer
## "More": payments, errors and announcements behind one tab.

var app: Node
var _subs := {}
var _btns := {}
var _cur := "pay"


func _init() -> void:
	add_theme_constant_override("separation", 8)
	var row := GridContainer.new()
	row.columns = 4
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	add_child(row)
	var defs := [["pay", "المدفوعات", APayments], ["err", "الأخطاء", AErrors], ["ann", "الإعلانات", AAnnounce], ["sup", "الدعم", ASupport],
			["ctl", "التحكم", AControl], ["brd", "الصدارة", ABoard], ["aud", "السجل", AAudit], ["sec", "الأمان", ASecurity]]
	for d in defs:
		var id: String = d[0]
		var b := AUI.btn(row, d[1], func(): _show(id), AUI.PANEL, 15, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_btns[id] = b
	for d in defs:
		var p: Control = d[2].new()
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(p)
		_subs[d[0]] = p
	_paint()


func _ready() -> void:
	for k in _subs:
		_subs[k].set("app", app)


func _paint() -> void:
	for k in _subs:
		(_subs[k] as Control).visible = k == _cur
		var b: Button = _btns[k]
		var on: bool = k == _cur
		var col := AUI.ACCENT
		b.add_theme_color_override("font_color", col if on else AUI.TXT)
		for sn in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(sn, AUI.sb(Color(col.r, col.g, col.b, 0.16) if on else Color(1, 1, 1, 0.09), 21, Color(col.r, col.g, col.b, 0.6) if on else Color(1, 1, 1, 0.12), 1))


func show_sub(id: String) -> void:
	_show(id)


func _show(id: String) -> void:
	_cur = id
	_paint()
	refresh()


func refresh() -> void:
	for k in _subs:
		_subs[k].set("app", app)
	if _subs.has(_cur):
		_subs[_cur].call("refresh")
