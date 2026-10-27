# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
extends Control
## Sabak Admin: login screen, then five pages (home, codes, events, payments, errors).

var _pages := {}
var _nav := {}
var _cur := ""
var _title: Label
var _games: OptionButton
var _body: Control
var _toast: Label


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	var bg := ColorRect.new()
	bg.color = AUI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if Api.url != "" and Api.key != "":
		Api.get_json("ping", func(code: int, _d: Dictionary):
			if code == 200:
				_show_app()
			else:
				_show_login(""))
		_show_login("...")
	else:
		_show_login("")


func say(msg: String, good := true) -> void:
	if _toast == null:
		_toast = AUI.lbl(self, "", 20, AUI.TXT)
		_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_toast.offset_top = -190
		_toast.offset_bottom = -140
		_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_toast.add_theme_stylebox_override("normal", AUI.sb(Color(0, 0, 0, 0.85), 22, AUI.LINE, 1))
	_toast.text = "  " + msg + "  "
	_toast.add_theme_color_override("font_color", AUI.OK if good else AUI.BAD)
	_toast.visible = true
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _clear_ui() -> void:
	for c in get_children():
		if c is ColorRect or c == _toast:
			continue
		c.queue_free()
	_pages.clear()
	_nav.clear()


# ------------------------------------------------------------------ login
func _show_login(status: String) -> void:
	_clear_ui()
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 28)
	add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var t := AUI.lbl(v, "سَبَك  Sabak Admin", 40, AUI.TXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := AUI.lbl(v, "لوحة إدارة ألعاب الشركة", 20, AUI.TXT2)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var u := AUI.field(v, "عنوان السيرفر", Api.url, false, "https://api.example.com")
	var k := AUI.field(v, "مفتاح الإدارة", Api.key)
	k.secret = true
	var msg := AUI.lbl(v, status, 18, AUI.BAD, true)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	AUI.btn(v, "دخول", func():
		Api.url = u.text.strip_edges()
		Api.key = k.text.strip_edges()
		if not Api.url.begins_with("http"):
			msg.text = "اكتب العنوان كاملاً مع http:// أو https://"
			return
		msg.text = "..."
		Api.get_json("ping", func(code: int, _d: Dictionary):
			if code == 200:
				Api.save()
				_show_app()
			elif code == 401:
				msg.text = "المفتاح غير صحيح"
			else:
				msg.text = "تعذر الاتصال بالسيرفر"), AUI.ACCENT, 24, 62)


# ------------------------------------------------------------------ app shell
func _show_app() -> void:
	_clear_ui()
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	# top bar
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", AUI.sb(AUI.PANEL, 0))
	col.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	top.add_child(th)
	_title = AUI.lbl(th, "", 26, AUI.TXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_games = OptionButton.new()
	_games.custom_minimum_size = Vector2(170, 46)
	for sn in ["normal", "hover", "pressed", "focus"]:
		_games.add_theme_stylebox_override(sn, AUI.sb(AUI.CARD, 10, AUI.LINE, 1))
	_games.add_theme_color_override("font_color", AUI.TXT)
	_games.add_theme_color_override("font_hover_color", AUI.TXT)
	_games.add_theme_font_size_override("font_size", 17)
	_games.item_selected.connect(func(i: int):
		Api.game = "" if i == 0 else Api.games[i - 1]
		Api.save()
		_refresh())
	th.add_child(_games)
	AUI.btn(th, "تحديث", func(): _refresh(), AUI.CARD, 17, 46)
	AUI.btn(th, "خروج", func():
		Api.logout()
		_show_login(""), AUI.CARD, 17, 46)
	var mm := MarginContainer.new()
	mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for s in ["left", "right", "top", "bottom"]:
		mm.add_theme_constant_override("margin_" + s, 14)
	col.add_child(mm)
	_body = Control.new()
	mm.add_child(_body)
	# pages
	var defs := [["home", "الرئيسية", AHome], ["codes", "الأكواد", ACodes], ["events", "الفعاليات", AEvents], ["pay", "المدفوعات", APayments], ["err", "الأخطاء", AErrors]]
	for d in defs:
		var p: Control = d[2].new()
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.visible = false
		p.set("app", self)
		_body.add_child(p)
		_pages[d[0]] = p
	# bottom nav
	var nav := PanelContainer.new()
	nav.add_theme_stylebox_override("panel", AUI.sb(AUI.PANEL, 0))
	col.add_child(nav)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 6)
	nav.add_child(nh)
	for d in defs:
		var b := Button.new()
		b.text = d[1]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 62)
		b.add_theme_font_size_override("font_size", 17)
		var id: String = d[0]
		b.pressed.connect(func(): _open(id))
		nh.add_child(b)
		_nav[id] = b
	_open("home")
	# list of games for the filter
	Api.get_json("summary", func(code: int, s: Dictionary):
		if code != 200:
			return
		Api.games = s.get("games", [])
		_games.clear()
		_games.add_item("كل الألعاب")
		var sel := 0
		for i in Api.games.size():
			_games.add_item(str(Api.games[i]))
			if Api.games[i] == Api.game:
				sel = i + 1
		_games.select(sel))


func _open(id: String) -> void:
	_cur = id
	for k in _pages:
		(_pages[k] as Control).visible = (k == id)
		var b: Button = _nav[k]
		var on: bool = k == id
		for sn in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(sn, AUI.sb(Color(1.0, 0.47, 0.1, 0.16) if on else Color(0, 0, 0, 0), 10, AUI.ACCENT if on else Color.TRANSPARENT, 2 if on else 0))
		b.add_theme_color_override("font_color", AUI.ACCENT if on else AUI.TXT2)
		b.add_theme_color_override("font_hover_color", AUI.ACCENT if on else AUI.TXT)
		b.add_theme_color_override("font_pressed_color", AUI.ACCENT)
	_title.text = {"home": "الرئيسية", "codes": "الأكواد", "events": "الفعاليات", "pay": "المدفوعات", "err": "الأخطاء"}[id]
	_refresh()


func _refresh() -> void:
	if _pages.has(_cur):
		_pages[_cur].call("refresh")
