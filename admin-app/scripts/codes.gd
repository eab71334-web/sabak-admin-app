# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name ACodes
extends VBoxContainer
## Redeem codes: list, create (one custom or many generated), enable/disable, delete.

var app: Node
var _list: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	AUI.btn(self, "+  كود جديد", _new_form, AUI.ACCENT, 22, 56)
	_list = AUI.scroll_page(self)


func refresh() -> void:
	Api.get_json("codes", func(code: int, d: Dictionary):
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
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL)


func _confirm_delete(code_s: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "حذف الكود %s نهائياً؟" % code_s
	dlg.ok_button_text = "حذف"
	dlg.cancel_button_text = "إلغاء"
	dlg.confirmed.connect(func():
		Api.post_json("code/delete", {"code": code_s}, func(_h, _d): refresh()))
	add_child(dlg)
	dlg.popup_centered(Vector2i(520, 200))


func _new_form() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "كود جديد"
	dlg.ok_button_text = "إغلاق"
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(600, 760)
	dlg.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	var coins := AUI.field(v, "عملات", "5000", true)
	var gems := AUI.field(v, "جواهر", "20", true)
	var uses := AUI.field(v, "عدد مرات الاستخدام الكلي (0 = بلا حد)", "1", true)
	var days := AUI.field(v, "صلاحية بالأيام (0 = بلا انتهاء)", "30", true)
	var count := AUI.field(v, "عدد الأكواد المولّدة (1 - 200)", "1", true)
	var custom := AUI.field(v, "كود مخصص (اختياري، مع عدد 1 فقط)", "", false, "WELCOME")
	var game := AUI.field(v, "اللعبة (فارغ = كل الألعاب)", Api.game, false, "hairpin")
	var note := AUI.field(v, "ملاحظة", "")
	var out := AUI.lbl(v, "", 20, AUI.OK, true)
	out.selectable = false
	AUI.btn(v, "إنشاء", func():
		Api.post_json("codes", {"coins": int(coins.text), "gems": int(gems.text), "max_uses": int(uses.text), "expires_days": float(days.text), "count": int(count.text),
				"code": custom.text.strip_edges(), "game": game.text.strip_edges(), "note": note.text}, func(_h: int, d: Dictionary):
			if d.get("ok", false):
				var made: Array = d.get("codes", [])
				out.text = "\n".join(made)
				out.add_theme_color_override("font_color", AUI.OK)
				DisplayServer.clipboard_set("\n".join(made))
				app.say("تم إنشاء %d وتم نسخها" % made.size())
				refresh()
			else:
				out.text = "الكود موجود مسبقاً" if str(d.get("error", "")) == "exists" else "فشل الإنشاء"
				out.add_theme_color_override("font_color", AUI.BAD)), AUI.ACCENT, 22, 56)
	add_child(dlg)
	dlg.popup_centered(Vector2i(660, 880))
