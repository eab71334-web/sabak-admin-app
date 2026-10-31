# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name ACodes
extends VBoxContainer
## Redeem codes: list, create (one custom or many generated), enable/disable, delete.

var app: Node
var _list: VBoxContainer
var _q: LineEdit


func _init() -> void:
	add_theme_constant_override("separation", 8)
	AUI.btn(self, "+  كود جديد", _new_form, AUI.ACCENT, 22, 56)
	_q = AUI.search_box(self, "بحث في الأكواد", func(t: String): AUI.apply_filter(_list, t))
	_list = AUI.scroll_page(self)


func refresh() -> void:
	Api.get_json("codes", func(code: int, d: Dictionary):
		if not is_instance_valid(_list):
			return
		for c in _list.get_children():
			c.queue_free()
		if code != 200:
			AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
			return
		var codes: Array = d.get("codes", [])
		if codes.is_empty():
			AUI.lbl(_list, "لا توجد أكواد بعد", 18, AUI.TXT2)
		for cd in codes:
			var c := AUI.card(_list)
			var hr := HBoxContainer.new()
			c.add_child(hr)
			var t := AUI.lbl(hr, str(cd["code"]), 24, AUI.GOLD if int(cd["active"]) == 1 else AUI.TXT2)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var code_s := str(cd["code"])
			AUI.btn(hr, "نسخ", func():
				DisplayServer.clipboard_set(code_s)
				app.say("تم النسخ"), AUI.PANEL, 16, 40)
			var parts := []
			if int(cd["coins"]) > 0:
				parts.append("%d عملة" % int(cd["coins"]))
			if int(cd["gems"]) > 0:
				parts.append("%d جوهرة" % int(cd["gems"]))
			AUI.lbl(c, " + ".join(parts), 18, AUI.TXT)
			var maxu := int(cd["max_uses"])
			var exp_s := "بلا انتهاء" if int(cd["expires_at"]) == 0 else "ينتهي " + AUI.when(int(cd["expires_at"]))
			AUI.lbl(c, "استُخدم %d / %s    |    %s    |    %s" % [int(cd["used"]), str(maxu) if maxu > 0 else "∞", exp_s, str(cd["game"]) if str(cd["game"]) != "" else "كل الألعاب"], 15, AUI.TXT2, true)
			if str(cd["note"]) != "":
				AUI.lbl(c, str(cd["note"]), 15, AUI.TXT2, true)
			var br := HBoxContainer.new()
			br.add_theme_constant_override("separation", 8)
			c.add_child(br)
			var active := int(cd["active"]) == 1
			var b1 := AUI.btn(br, "إيقاف" if active else "تفعيل", func():
				Api.post_json("code/toggle", {"code": code_s, "active": not active}, func(_h, _d): refresh()), AUI.PANEL, 17, 44)
			b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b2 := AUI.btn(br, "حذف", func(): _confirm_delete(code_s), AUI.PANEL, 17, 44)
			b2.add_theme_color_override("font_color", AUI.BAD)
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		AUI.apply_filter(_list, _q.text))


func _confirm_delete(code_s: String) -> void:
	AModal.confirm(app, "حذف الكود", "سيُحذف الكود %s نهائياً ولا يمكن التراجع." % code_s, "حذف",
		func(): Api.post_json("code/delete", {"code": code_s}, func(_h, _d): refresh()))


func _new_form() -> void:
	var m := AModal.open(app, "كود جديد")
	var v := m.content
	var tpl := HBoxContainer.new()
	tpl.add_theme_constant_override("separation", 8)
	v.add_child(tpl)
	var coins := AUI.field(v, "عملات", "5000", true)
	var gems := AUI.field(v, "جواهر", "20", true)
	var uses := AUI.field(v, "عدد مرات الاستخدام الكلي (0 = بلا حد)", "1", true)
	var days := AUI.field(v, "صلاحية بالأيام (0 = بلا انتهاء)", "30", true)
	var count := AUI.field(v, "عدد الأكواد المولّدة (1 - 200)", "1", true)
	var custom := AUI.field(v, "كود مخصص (اختياري، مع عدد 1 فقط)", "", false, "WELCOME")
	var game := AUI.field(v, "اللعبة (فارغ = كل الألعاب)", Api.game, false, "hairpin")
	var note := AUI.field(v, "ملاحظة", "")
	for t in [["هدية 5000", 5000, 20, 1, 30], ["كبيرة", 50000, 100, 1, 30], ["ترحيب 2000", 2000, 10, 0, 0]]:
		var tt: Array = t
		var tb := AUI.btn(tpl, tt[0], func():
			coins.text = str(tt[1])
			gems.text = str(tt[2])
			uses.text = str(tt[3])
			days.text = str(tt[4]), AUI.PANEL, 16, 40)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var out := AUI.lbl(v, "", 22, AUI.OK, true)
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var share := HBoxContainer.new()
	share.add_theme_constant_override("separation", 8)
	share.visible = false
	v.add_child(share)
	var made_txt := {"t": ""}
	var sb1 := AUI.btn(share, "نسخ الكل", func():
		DisplayServer.clipboard_set(str(made_txt["t"]))
		app.say("تم النسخ"), AUI.PANEL, 18, 46)
	sb1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb2 := AUI.btn(share, "واتساب", func():
		OS.shell_open("https://wa.me/?text=" + str(made_txt["t"]).uri_encode()), AUI.PANEL, 18, 46)
	sb2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb2.add_theme_color_override("font_color", AUI.OK)
	var busy := {"b": null, "on": false}
	busy["b"] = AUI.btn(v, "إنشاء", func():
		if busy["on"]:
			return
		busy["on"] = true
		(busy["b"] as Button).disabled = true
		Api.post_json("codes", {"coins": int(coins.text), "gems": int(gems.text), "max_uses": int(uses.text), "expires_days": float(days.text), "count": int(count.text),
				"code": custom.text.strip_edges(), "game": game.text.strip_edges(), "note": note.text}, func(_h: int, d: Dictionary):
			busy["on"] = false
			var bb: Variant = busy["b"]
			if bb != null and is_instance_valid(bb):
				(bb as Button).disabled = false
			if d.get("ok", false):
				var made: Array = d.get("codes", [])
				DisplayServer.clipboard_set("\n".join(made))
				app.say("تم إنشاء %d وتم نسخها" % made.size())
				refresh()
				if not is_instance_valid(out):
					return
				out.text = "\n".join(made)
				made_txt["t"] = "\n".join(made)
				share.visible = true
				out.add_theme_color_override("font_color", AUI.GOLD)
			else:
				if not is_instance_valid(out):
					return
				out.text = "الكود موجود مسبقاً" if str(d.get("error", "")) == "exists" else "فشل الإنشاء"
				out.add_theme_color_override("font_color", AUI.BAD)), AUI.ACCENT, 22, 58)
