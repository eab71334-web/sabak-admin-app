# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name AEvents
extends VBoxContainer
## Events: a time-limited announcement with an optional one-time reward every player can claim.

var app: Node
var _list: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	AUI.btn(self, "+  فعالية جديدة", _new_form, AUI.ACCENT, 22, 56)
	_list = AUI.scroll_page(self)


func refresh() -> void:
	Api.get_json("events", func(code: int, d: Dictionary):
		for c in _list.get_children():
			c.queue_free()
		if code != 200:
			AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
			return
		var evs: Array = d.get("events", [])
		if evs.is_empty():
			AUI.lbl(_list, "لا توجد فعاليات بعد", 18, AUI.TXT2)
		var now := int(Time.get_unix_time_from_system())
		for e in evs:
			var c := AUI.card(_list)
			var live := int(e["active"]) == 1 and int(e["ends_at"]) >= now
			AUI.lbl(c, str(e["title_ar"]) if str(e["title_ar"]) != "" else str(e["title"]), 24, AUI.TXT if live else AUI.TXT2)
			if str(e["body_ar"]) != "" or str(e["body"]) != "":
				AUI.lbl(c, str(e["body_ar"]) if str(e["body_ar"]) != "" else str(e["body"]), 16, AUI.TXT2, true)
			var rw := []
			if int(e["reward_coins"]) > 0:
				rw.append("%d عملة" % int(e["reward_coins"]))
			if int(e["reward_gems"]) > 0:
				rw.append("%d جوهرة" % int(e["reward_gems"]))
			AUI.lbl(c, ("الجائزة: " + " + ".join(rw) if not rw.is_empty() else "بدون جائزة") + "     |     استلمها %d لاعب" % int(e["claims"]), 16, AUI.GOLD, true)
			AUI.lbl(c, ("جارية حتى " if live else "منتهية/متوقفة - ") + AUI.when(int(e["ends_at"])), 15, AUI.OK if live else AUI.TXT2)
			var br := HBoxContainer.new()
			br.add_theme_constant_override("separation", 8)
			c.add_child(br)
			var eid := int(e["id"])
			var on := int(e["active"]) == 1
			var b1 := AUI.btn(br, "إيقاف" if on else "تفعيل", func():
				Api.post_json("event/toggle", {"id": eid, "active": not on}, func(_h, _d): refresh()), AUI.PANEL, 17, 44)
			b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b2 := AUI.btn(br, "حذف", func():
				Api.post_json("event/delete", {"id": eid}, func(_h, _d): refresh()), AUI.PANEL, 17, 44)
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL)


func _new_form() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "فعالية جديدة"
	dlg.ok_button_text = "إغلاق"
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(600, 800)
	dlg.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	var ta := AUI.field(v, "العنوان بالعربي", "")
	var te := AUI.field(v, "العنوان بالإنجليزي", "")
	var ba := AUI.field(v, "الوصف بالعربي", "")
	var be := AUI.field(v, "الوصف بالإنجليزي", "")
	var rc := AUI.field(v, "جائزة عملات", "0", true)
	var rg := AUI.field(v, "جائزة جواهر", "0", true)
	var days := AUI.field(v, "المدة بالأيام", "7", true)
	var game := AUI.field(v, "اللعبة (فارغ = كل الألعاب)", Api.game, false, "hairpin")
	var out := AUI.lbl(v, "", 18, AUI.OK, true)
	AUI.btn(v, "نشر الفعالية", func():
		if ta.text.strip_edges() == "" and te.text.strip_edges() == "":
			out.text = "اكتب عنواناً"
			out.add_theme_color_override("font_color", AUI.BAD)
			return
		Api.post_json("events", {"title": te.text, "title_ar": ta.text, "body": be.text, "body_ar": ba.text, "reward_coins": int(rc.text), "reward_gems": int(rg.text),
				"days": float(days.text), "game": game.text.strip_edges()}, func(_h: int, d: Dictionary):
			if d.get("ok", false):
				out.text = "تم النشر"
				out.add_theme_color_override("font_color", AUI.OK)
				refresh()
			else:
				out.text = "فشل النشر"
				out.add_theme_color_override("font_color", AUI.BAD)), AUI.ACCENT, 22, 56)
	var room := Control.new()   # lets the last fields scroll above the on-screen keyboard
	room.custom_minimum_size = Vector2(0, 330)
	v.add_child(room)
	add_child(dlg)
	dlg.popup_centered(Vector2i(660, 900))
