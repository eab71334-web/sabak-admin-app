# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name AAnnounce
extends VBoxContainer
## Announcements: a message every player sees once when the game opens (e.g. "maintenance tonight").

var app: Node
var _list: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	AUI.btn(self, "+  إعلان جديد", _new_form, AUI.ACCENT, 22, 56)
	_list = AUI.scroll_page(self)


func refresh() -> void:
	Api.get_json("announcements", func(code: int, d: Dictionary):
		if not is_instance_valid(_list):
			return
		for c in _list.get_children():
			c.queue_free()
		if code != 200:
			AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
			return
		var rows: Array = d.get("announcements", [])
		if rows.is_empty():
			AUI.lbl(_list, "لا توجد إعلانات", 18, AUI.TXT2)
		var now := int(Time.get_unix_time_from_system())
		for a in rows:
			var live := int(a["active"]) == 1 and (int(a["ends_at"]) == 0 or int(a["ends_at"]) >= now)
			var c := AUI.card(_list)
			AUI.lbl(c, str(a["text_ar"]) if str(a["text_ar"]) != "" else str(a["text"]), 20, AUI.TXT if live else AUI.TXT2, true)
			if str(a["text"]) != "" and str(a["text_ar"]) != "":
				AUI.lbl(c, str(a["text"]), 15, AUI.TXT2, true)
			AUI.lbl(c, ("ظاهر الآن" if live else "متوقف/منتهي") + "    |    " + (str(a["game"]) if str(a["game"]) != "" else "كل الألعاب") + ("" if int(a["ends_at"]) == 0 else "    |    حتى " + AUI.when(int(a["ends_at"]))), 14, AUI.OK if live else AUI.TXT2, true)
			var aid := int(a["id"])
			var br := HBoxContainer.new()
			br.add_theme_constant_override("separation", 8)
			c.add_child(br)
			var on := int(a["active"]) == 1
			var b1 := AUI.btn(br, "إيقاف" if on else "تفعيل", func():
				Api.post_json("announce/toggle", {"id": aid, "active": not on}, func(_h, _d): refresh()), AUI.PANEL, 17, 44)
			b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b2 := AUI.btn(br, "حذف", func():
				AModal.confirm(app, "حذف الإعلان", "سيُحذف هذا الإعلان نهائياً.", "حذف",
					func(): Api.post_json("announce/delete", {"id": aid}, func(_h, _d): refresh())), AUI.PANEL, 17, 44)
			b2.add_theme_color_override("font_color", AUI.BAD)
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL)


func _new_form() -> void:
	var m := AModal.open(app, "إعلان جديد")
	var v := m.content
	var tpl := HBoxContainer.new()
	tpl.add_theme_constant_override("separation", 8)
	v.add_child(tpl)
	var ta := AUI.field(v, "النص بالعربي", "")
	var te := AUI.field(v, "النص بالإنجليزي", "")
	var days := AUI.field(v, "يظهر لمدة (أيام، 0 = حتى تحذفه)", "1", true)
	var game := AUI.field(v, "اللعبة (فارغ = كل الألعاب)", Api.game, false, "hairpin")
	for t in [["صيانة", "صيانة قصيرة الليلة. قد تتوقف الخدمة قليلاً.", "Short maintenance tonight. Service may pause briefly."],
			["تحديث", "يتوفر تحديث جديد. حدّث اللعبة للحصول على الجديد!", "A new update is available. Update the game!"]]:
		var tt: Array = t
		var b := AUI.btn(tpl, tt[0], func():
			ta.text = tt[1]
			te.text = tt[2], AUI.PANEL, 16, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var out := AUI.lbl(v, "", 20, AUI.OK, true)
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var busy := {"b": null, "on": false}
	busy["b"] = AUI.btn(v, "نشر الإعلان", func():
		if busy["on"]:
			return
		if ta.text.strip_edges() == "" and te.text.strip_edges() == "":
			out.text = "اكتب نصاً"
			out.add_theme_color_override("font_color", AUI.BAD)
			return
		busy["on"] = true
		(busy["b"] as Button).disabled = true
		Api.post_json("announcements", {"text": te.text, "text_ar": ta.text, "days": float(days.text), "game": game.text.strip_edges()}, func(_h: int, d: Dictionary):
			busy["on"] = false
			var bb: Variant = busy["b"]
			if bb != null and is_instance_valid(bb):
				(bb as Button).disabled = false
			if d.get("ok", false):
				refresh()
				if is_instance_valid(m):
					m.close()
			elif is_instance_valid(out):
				out.text = "فشل النشر"
				out.add_theme_color_override("font_color", AUI.BAD)), AUI.ACCENT, 22, 58)
