# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name AControl
extends VBoxContainer
## Remote control of the games: maintenance, forced update, ads, reward multipliers, store prices.
## Settings apply to the game picked at the top ("all games" = every game).

var app: Node
var _list: VBoxContainer
var _cfg := {}
var _packs_default: Array = []


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_list = AUI.scroll_page(self)


func refresh() -> void:
	Api.get_json("gamecfg?game=" + Api.game.uri_encode(), func(code: int, d: Dictionary):
		if not is_instance_valid(_list):
			return
		for c in _list.get_children():
			c.queue_free()
		if code == 403:
			AUI.lbl(_list, "هذه الصفحة للمالك فقط", 20, AUI.BAD)
			return
		if code != 200:
			AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
			return
		_cfg = d.get("cfg", {})
		_packs_default = d.get("packs_default", [])
		_build())


func _put(key: String, value: Variant) -> void:
	Api.post_json("gamecfg", {"game": Api.game, "key": key, "value": value}, func(_h: int, d: Dictionary):
		if d.get("ok", false):
			app.say("تم الحفظ")
		refresh())


func _build() -> void:
	var sc := AUI.card(_list, Color(0.83, 0.68, 0.36, 0.1))
	AUI.lbl(sc, "الإعدادات تُطبَّق على: " + (Api.game if Api.game != "" else "كل الألعاب"), 18, AUI.GOLD, true)
	AUI.lbl(sc, "غيّر اللعبة من الزر العلوي. إعداد لعبة معيّنة يتفوّق على إعداد «كل الألعاب».", 14, AUI.TXT2, true)
	# ---- maintenance
	var m: Dictionary = _cfg.get("maintenance", {})
	var m_on := bool(m.get("on", false))
	var c1 := AUI.card(_list)
	AUI.lbl(c1, "وضع الصيانة", 22, AUI.TXT)
	AUI.lbl(c1, "اللعبة متوقفة الآن للاعبين" if m_on else "اللعبة تعمل طبيعياً", 16, AUI.BAD if m_on else AUI.OK)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	c1.add_child(r1)
	var b1 := AUI.btn(r1, "إيقاف الصيانة" if m_on else "تشغيل الصيانة", func():
		AModal.confirm(app, "وضع الصيانة", "سيُمنع اللاعبون من الدخول حتى تُوقفه." if not m_on else "ستعود اللعبة للعمل.", "تأكيد",
			func(): _put("maintenance", {"on": not m_on, "text": str(m.get("text", "")), "text_ar": str(m.get("text_ar", ""))}), not m_on), AUI.PANEL, 17, 46)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b1.add_theme_color_override("font_color", AUI.OK if m_on else AUI.BAD)
	var b1b := AUI.btn(r1, "تعديل الرسالة", func(): _maint_form(m), AUI.PANEL, 17, 46)
	b1b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ---- force update
	var u: Dictionary = _cfg.get("update", {})
	var c2 := AUI.card(_list)
	AUI.lbl(c2, "إجبار التحديث", 22, AUI.TXT)
	AUI.lbl(c2, ("أدنى نسخة مسموحة: " + str(u.get("min_version", ""))) if str(u.get("min_version", "")) != "" else "غير مفعّل", 16, AUI.GOLD if str(u.get("min_version", "")) != "" else AUI.TXT2)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	c2.add_child(r2)
	var b2 := AUI.btn(r2, "تعديل", func(): _update_form(u), AUI.PANEL, 17, 46)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if str(u.get("min_version", "")) != "":
		var b2b := AUI.btn(r2, "إلغاء الإجبار", func(): _put("update", null), AUI.PANEL, 17, 46)
		b2b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b2b.add_theme_color_override("font_color", AUI.BAD)
	# ---- ads
	var ads: Dictionary = _cfg.get("ads", {})
	var c3 := AUI.card(_list)
	AUI.lbl(c3, "الإعلانات", 22, AUI.TXT)
	_tri(c3, "الإعلانات مفعّلة", ads, "enabled", ["حسب اللعبة", "نعم", "لا"])
	_tri(c3, "البانر", ads, "live_banner", ["حسب اللعبة", "حقيقي", "تجريبي"])
	_tri(c3, "إعلان المكافأة", ads, "live_rewarded", ["حسب اللعبة", "حقيقي", "تجريبي"])
	AUI.lbl(c3, "إيقاف الإعلانات يسري فوراً. تبديل حقيقي/تجريبي يسري عند فتح اللعبة في المرة القادمة. لا تضغط على إعلان حقيقي بنفسك.", 13, AUI.TXT2, true)
	# ---- reward multipliers
	var rc: Dictionary = _cfg.get("rc", {})
	var c4 := AUI.card(_list)
	AUI.lbl(c4, "جوائز اللعبة", 22, AUI.TXT)
	AUI.lbl(c4, "صناديق ×%s   |   سباقات ×%s   |   مهام ×%s   |   صناديق الإعلان %s/يوم" % [str(rc.get("chest_mult", 1)), str(rc.get("reward_mult", 1)), str(rc.get("quest_mult", 1)), str(rc.get("adbox_per_day", 3))], 15, AUI.TXT2, true)
	var b4 := AUI.btn(c4, "تعديل الجوائز", func(): _rc_form(rc), AUI.PANEL, 17, 46)
	b4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ---- store prices
	var c5 := AUI.card(_list)
	AUI.lbl(c5, "أسعار المتجر", 22, AUI.TXT)
	AUI.lbl(c5, "مخصّصة لهذه اللعبة" if _cfg.has("packs") else "الأسعار الافتراضية", 15, AUI.GOLD if _cfg.has("packs") else AUI.TXT2)
	var r5 := HBoxContainer.new()
	r5.add_theme_constant_override("separation", 8)
	c5.add_child(r5)
	var b5 := AUI.btn(r5, "تعديل الأسعار", func(): _packs_form(), AUI.PANEL, 17, 46)
	b5.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _cfg.has("packs"):
		var b5b := AUI.btn(r5, "إرجاع الافتراضي", func(): _put("packs", null), AUI.PANEL, 17, 46)
		b5b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b5b.add_theme_color_override("font_color", AUI.BAD)


## three-state switch stored inside dictionary `d` under `_cfg[<group>]`; labels = [absent, true, false]
func _tri(parent: Node, title: String, d: Dictionary, key: String, labels: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var t := AUI.lbl(row, title, 17, AUI.TXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var cur := 0
	if d.has(key):
		cur = 1 if bool(d[key]) else 2
	var b := AUI.btn(row, str(labels[cur]), func():
		var nd := d.duplicate()
		match cur:
			0:
				nd[key] = true
			1:
				nd[key] = false
			_:
				nd.erase(key)
		_put("ads", nd if not nd.is_empty() else null), AUI.PANEL, 16, 42)
	b.custom_minimum_size = Vector2(140, 42)
	if cur == 1:
		b.add_theme_color_override("font_color", AUI.ACCENT)


func _maint_form(m: Dictionary) -> void:
	var md := AModal.open(app, "رسالة الصيانة")
	var v := md.content
	var ta := AUI.field(v, "النص بالعربي", str(m.get("text_ar", "")), false, "نقوم بتحسينات، نعود قريباً")
	var te := AUI.field(v, "النص بالإنجليزي", str(m.get("text", "")), false, "Back soon")
	AUI.btn(v, "حفظ", func():
		md.close()
		_put("maintenance", {"on": bool(m.get("on", false)), "text": te.text, "text_ar": ta.text}), AUI.ACCENT, 22, 56)


func _update_form(u: Dictionary) -> void:
	var md := AModal.open(app, "إجبار التحديث")
	var v := md.content
	AUI.lbl(v, "اللاعب الذي نسخته أقدم من هذه النسخة لا يدخل قبل أن يحدّث. النسخة الحالية للعبة 1.0.", 15, AUI.TXT2, true)
	var mv := AUI.field(v, "أدنى نسخة مسموحة (مثل 1.1)", str(u.get("min_version", "")), false, "1.1")
	var ta := AUI.field(v, "الرسالة بالعربي", str(u.get("text_ar", "")), false, "يوجد تحديث جديد. حدّث اللعبة للمتابعة.")
	var te := AUI.field(v, "الرسالة بالإنجليزي", str(u.get("text", "")), false, "A new update is required.")
	var url := AUI.field(v, "رابط التحديث (اختياري)", str(u.get("url", "")), false, "https://...")
	AUI.btn(v, "حفظ", func():
		md.close()
		_put("update", {"min_version": mv.text.strip_edges(), "text": te.text, "text_ar": ta.text, "url": url.text.strip_edges()} if mv.text.strip_edges() != "" else null), AUI.ACCENT, 22, 56)


func _rc_form(rc: Dictionary) -> void:
	var md := AModal.open(app, "جوائز اللعبة")
	var v := md.content
	AUI.lbl(v, "1 = كما هي. 2 = الضعف. 0.5 = النصف. اترك الخانة فارغة للافتراضي.", 15, AUI.TXT2, true)
	var f1 := AUI.field(v, "مضاعف جوائز الصناديق", str(rc["chest_mult"]) if rc.has("chest_mult") else "", true, "1")
	var f2 := AUI.field(v, "مضاعف مكافآت السباقات", str(rc["reward_mult"]) if rc.has("reward_mult") else "", true, "1")
	var f3 := AUI.field(v, "مضاعف مكافآت المهام", str(rc["quest_mult"]) if rc.has("quest_mult") else "", true, "1")
	var f4 := AUI.field(v, "صناديق الإعلان في اليوم", str(rc["adbox_per_day"]) if rc.has("adbox_per_day") else "", true, "3")
	AUI.btn(v, "حفظ", func():
		var o := {}
		for p in [["chest_mult", f1], ["reward_mult", f2], ["quest_mult", f3], ["adbox_per_day", f4]]:
			var t: String = (p[1] as LineEdit).text.strip_edges()
			if t.is_valid_float():
				o[p[0]] = clampf(float(t), 0.0, 20.0)
		md.close()
		_put("rc", o if not o.is_empty() else null), AUI.ACCENT, 22, 56)


func _packs_form() -> void:
	var md := AModal.open(app, "أسعار المتجر")
	var v := md.content
	AUI.lbl(v, "السعر بالدولار والكمية. هذا ما يُحاسَب به اللاعب فعلاً.", 15, AUI.TXT2, true)
	var src: Array = _cfg.get("packs", _packs_default)
	var rows: Array = []
	for p in src:
		AUI.lbl(v, "%s  (%s)" % [str(p["id"]), "عملات" if str(p["kind"]) == "coins" else "جواهر"], 16, AUI.GOLD)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		v.add_child(hb)
		var pr := AUI.field(hb, "السعر $", str(p["price_usd"]), true)
		var am := AUI.field(hb, "الكمية", str(int(p["amount"])), true)
		rows.append([p, pr, am])
	AUI.btn(v, "حفظ", func():
		var out: Array = []
		for r in rows:
			var p: Dictionary = (r[0] as Dictionary).duplicate()
			var pr := float((r[1] as LineEdit).text)
			var am := int((r[2] as LineEdit).text)
			if pr > 0.0 and am > 0:
				p["price_usd"] = pr
				p["amount"] = am
			out.append(p)
		md.close()
		_put("packs", out), AUI.ACCENT, 22, 56)
