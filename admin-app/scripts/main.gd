# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
extends Control
## Sabak Admin: login screen, then five pages (home, codes, events, payments, errors).

var _pages := {}
var _nav := {}
var _cur := ""
var _title: Label
var _games: Button
var _body: Control
var _toast: Label


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	var bg := ColorRect.new()
	bg.color = AUI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 0.75)
	gt.width = 256
	gt.height = 256
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(AUI.ACCENT.r, AUI.ACCENT.g, AUI.ACCENT.b, 0.20), Color(AUI.ACCENT.r, AUI.ACCENT.g, AUI.ACCENT.b, 0.0)])
	gt.gradient = gr
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)
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
		if c is ColorRect or c is TextureRect or c == _toast:
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
	var ins0 := AUI.insets(self)
	m.add_theme_constant_override("margin_top", 28 + int(ins0["top"]))
	m.add_theme_constant_override("margin_bottom", 28 + int(ins0["bottom"]))
	add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var lg := ALogo.new(120)
	lg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(lg)
	var t := AUI.lbl(v, "SABAK", 44, AUI.TXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := AUI.lbl(v, "لوحة إدارة الألعاب", 20, AUI.ACCENT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var u := AUI.field(v, "عنوان السيرفر", Api.url, false, "https://api.example.com")
	u.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
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
	var ins := AUI.insets(self)
	var top := MarginContainer.new()
	top.add_theme_constant_override("margin_top", int(ins["top"]) + 10)
	top.add_theme_constant_override("margin_bottom", 8)
	top.add_theme_constant_override("margin_left", 16)
	top.add_theme_constant_override("margin_right", 16)
	col.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	top.add_child(th)
	var lg := ALogo.new(46)
	th.add_child(lg)
	_title = AUI.lbl(th, "", 30, AUI.TXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_games = AUI.btn(th, "", func(): _pick_game(), AUI.PANEL, 16, 44)
	_games.custom_minimum_size = Vector2(150, 44)
	_games.clip_text = true
	_set_game_label()
	AUI.btn(th, "تحديث", func(): _refresh(), AUI.PANEL, 16, 44)
	AUI.btn(th, "خروج", func():
		Api.logout()
		_show_login(""), AUI.PANEL, 16, 44)
	var mm := MarginContainer.new()
	mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for s in ["left", "right", "top", "bottom"]:
		mm.add_theme_constant_override("margin_" + s, 16)
	mm.add_theme_constant_override("margin_top", 6)
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
	var navm := MarginContainer.new()
	navm.add_theme_constant_override("margin_left", 14)
	navm.add_theme_constant_override("margin_right", 14)
	navm.add_theme_constant_override("margin_top", 4)
	navm.add_theme_constant_override("margin_bottom", 6 + int(ins["bottom"]))
	col.add_child(navm)
	var nav := PanelContainer.new()
	var nav_sb := AUI.sb(Color(0.09, 0.09, 0.1, 0.96), 36, Color(1, 1, 1, 0.14), 1)
	nav_sb.content_margin_left = 8
	nav_sb.content_margin_right = 8
	nav_sb.content_margin_top = 8
	nav_sb.content_margin_bottom = 8
	nav_sb.shadow_color = Color(0, 0, 0, 0.6)
	nav_sb.shadow_size = 18
	nav.add_theme_stylebox_override("panel", nav_sb)
	navm.add_child(nav)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 4)
	nav.add_child(nh)
	for d in defs:
		var b := Button.new()
		b.text = d[1]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_size_override("font_size", 16)
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
		_set_game_label())


func _set_game_label() -> void:
	if _games != null and is_instance_valid(_games):
		_games.text = (Api.game if Api.game != "" else "كل الألعاب") + "  ▾"


func _pick_game() -> void:
	var m := AModal.open(self, "اللعبة")
	var opts: Array = [""]
	opts.append_array(Api.games)
	for g in opts:
		var gs := str(g)
		var on := gs == Api.game
		var b := AUI.btn(m.content, gs if gs != "" else "كل الألعاب", func():
			Api.game = gs
			Api.save()
			_set_game_label()
			m.close()
			_refresh(), AUI.PANEL, 20, 54)
		if on:
			b.add_theme_color_override("font_color", AUI.ACCENT)
			b.add_theme_color_override("font_hover_color", AUI.ACCENT)
			b.add_theme_color_override("font_pressed_color", AUI.ACCENT)
			for k in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(k, AUI.sb(Color(AUI.ACCENT.r, AUI.ACCENT.g, AUI.ACCENT.b, 0.16), 27, Color(AUI.ACCENT.r, AUI.ACCENT.g, AUI.ACCENT.b, 0.7), 1))


func _open(id: String) -> void:
	_cur = id
	for k in _pages:
		(_pages[k] as Control).visible = (k == id)
		var b: Button = _nav[k]
		var on: bool = k == id
		for sn in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(sn, AUI.sb(Color(AUI.ACCENT.r, AUI.ACCENT.g, AUI.ACCENT.b, 0.16) if on else Color(0, 0, 0, 0), 26, Color(AUI.ACCENT.r, AUI.ACCENT.g, AUI.ACCENT.b, 0.55) if on else Color.TRANSPARENT, 1 if on else 0))
		b.add_theme_color_override("font_color", AUI.ACCENT if on else AUI.TXT2)
		b.add_theme_color_override("font_hover_color", AUI.ACCENT if on else AUI.TXT)
		b.add_theme_color_override("font_pressed_color", AUI.ACCENT)
	_title.text = {"home": "الرئيسية", "codes": "الأكواد", "events": "الفعاليات", "pay": "المدفوعات", "err": "الأخطاء"}[id]
	_refresh()


func _refresh() -> void:
	if _pages.has(_cur):
		_pages[_cur].call("refresh")
