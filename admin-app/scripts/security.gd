# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name ASecurity
extends VBoxContainer
## Security: PIN lock, helper keys with limited roles, data export.

var app: Node
var _list: VBoxContainer

const ROLES := {"editor": "محرّر (يدير الأكواد والفعاليات والرسائل، بلا حذف أو حظر)", "viewer": "مشاهد (قراءة فقط)"}


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_list = AUI.scroll_page(self)


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	# ---- PIN
	var c1 := AUI.card(_list)
	AUI.lbl(c1, "قفل التطبيق", 22, AUI.TXT)
	var has_pin := Api.pin_hash != ""
	AUI.lbl(c1, "مفعّل: يُطلب الرقم السري عند فتح التطبيق" if has_pin else "غير مفعّل", 16, AUI.OK if has_pin else AUI.TXT2)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	c1.add_child(r1)
	var b1 := AUI.btn(r1, "تغيير الرقم" if has_pin else "تعيين رقم سري", func(): _pin_form(), AUI.PANEL, 17, 46)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if has_pin:
		var b1b := AUI.btn(r1, "إزالة", func():
			Api.pin_hash = ""
			Api.save()
			app.say("أُزيل القفل")
			refresh(), AUI.PANEL, 17, 46)
		b1b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b1b.add_theme_color_override("font_color", AUI.BAD)
	# ---- export
	var c2 := AUI.card(_list)
	AUI.lbl(c2, "تصدير البيانات (CSV)", 22, AUI.TXT)
	AUI.lbl(c2, "يُنسخ للحافظة ويُحفظ في الملفات (Sabak Admin). يلتزم باللعبة المختارة في الأعلى.", 14, AUI.TXT2, true)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	c2.add_child(r2)
	for e in [["players", "اللاعبون"], ["payments", "المدفوعات"], ["codes", "الأكواد"]]:
		var what: String = e[0]
		var b := AUI.btn(r2, e[1], func(): _export(what), AUI.PANEL, 17, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ---- keys
	var c3 := AUI.card(_list)
	AUI.lbl(c3, "مفاتيح المساعدين", 22, AUI.TXT)
	AUI.lbl(c3, "أعطِ مساعدك مفتاحاً خاصاً بدل مفتاحك الأساسي. تحذفه متى شئت.", 14, AUI.TXT2, true)
	AUI.btn(c3, "+  مفتاح جديد", func(): _key_form(), AUI.ACCENT, 19, 48)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	c3.add_child(holder)
	Api.get_json("keys", func(code: int, d: Dictionary):
		if not is_instance_valid(holder):
			return
		if code == 403:
			AUI.lbl(holder, "إدارة المفاتيح للمالك فقط", 15, AUI.BAD)
			return
		for k in d.get("keys", []):
			var kid := int(k["id"])
			var row := AUI.card(holder)
			var hr := HBoxContainer.new()
			row.add_child(hr)
			var t := AUI.lbl(hr, "%s  -  %s" % [str(k["name"]), "محرّر" if str(k["role"]) == "editor" else "مشاهد"], 18, AUI.TXT)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var del := AUI.btn(hr, "حذف", func():
				AModal.confirm(app, "حذف المفتاح", "سيفقد صاحبه الدخول فوراً.", "حذف",
					func(): Api.post_json("key/delete", {"id": kid}, func(_h, _d): refresh())), AUI.PANEL, 15, 38)
			del.add_theme_color_override("font_color", AUI.BAD))


func _export(what: String) -> void:
	Api.get_json("export?what=" + what, func(code: int, d: Dictionary):
		if code != 200 or not d.get("ok", false):
			app.say("فشل التصدير", false)
			return
		var csv := str(d.get("csv", ""))
		DisplayServer.clipboard_set(csv)
		DirAccess.make_dir_recursive_absolute("user://exports")
		var f := FileAccess.open("user://exports/%s.csv" % what, FileAccess.WRITE)
		if f:
			f.store_string("﻿" + csv)
		app.say("تم النسخ وحُفظ الملف %s.csv" % what))


func _pin_form() -> void:
	var md := AModal.open(app, "الرقم السري")
	var v := md.content
	var a := AUI.field(v, "رقم من 4 أرقام", "", true)
	var b := AUI.field(v, "أعد كتابته", "", true)
	var out := AUI.lbl(v, "", 18, AUI.BAD, true)
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	AUI.btn(v, "حفظ", func():
		var p := a.text.strip_edges()
		if p.length() != 4 or not p.is_valid_int():
			out.text = "اكتب 4 أرقام"
			return
		if p != b.text.strip_edges():
			out.text = "الرقمان غير متطابقين"
			return
		Api.pin_hash = ALock.hash_pin(p)
		Api.save()
		md.close()
		app.say("تم تفعيل القفل")
		refresh(), AUI.ACCENT, 22, 56)


func _key_form() -> void:
	var md := AModal.open(app, "مفتاح جديد")
	var v := md.content
	var nm := AUI.field(v, "اسم المساعد", "")
	var role := {"v": "editor"}
	var rb: Array = []
	for r in ["editor", "viewer"]:
		var id: String = r
		var b := AUI.btn(v, str(ROLES[id]), func():
			role["v"] = id
			for x in rb:
				(x[1] as Button).add_theme_color_override("font_color", AUI.ACCENT if x[0] == id else AUI.TXT), AUI.PANEL, 15, 48)
		b.add_theme_color_override("font_color", AUI.ACCENT if id == "editor" else AUI.TXT)
		rb.append([id, b])
	var out := AUI.lbl(v, "", 20, AUI.GOLD, true)
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var done := {"on": false}
	AUI.btn(v, "إنشاء المفتاح", func():
		if done["on"]:
			return
		done["on"] = true
		Api.post_json("key/create", {"name": nm.text.strip_edges() if nm.text.strip_edges() != "" else "مساعد", "role": role["v"]}, func(_h: int, d: Dictionary):
			if d.get("ok", false) and is_instance_valid(out):
				out.text = "المفتاح (يظهر مرة واحدة، تم نسخه):\n" + str(d["key"])
				DisplayServer.clipboard_set(str(d["key"]))
				refresh()
			else:
				done["on"] = false), AUI.ACCENT, 22, 56)
