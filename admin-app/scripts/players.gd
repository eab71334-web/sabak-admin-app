# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name APlayers
extends VBoxContainer
## Players: search, last seen, gift coins/gems, ban / unban.

var app: Node
var _list: VBoxContainer
var _q: LineEdit
var _timer: Timer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_q = AUI.search_box(self, "بحث باسم اللاعب أو رقمه", func(_t: String): _later())
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.5
	_timer.timeout.connect(func(): refresh())
	add_child(_timer)
	_list = AUI.scroll_page(self)


func _later() -> void:
	_timer.start()


func refresh() -> void:
	var term := _q.text.strip_edges()
	Api.get_json("players?q=" + term.uri_encode(), func(code: int, d: Dictionary):
		if not is_instance_valid(_list):
			return
		for c in _list.get_children():
			c.queue_free()
		if code != 200:
			AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
			return
		var rows: Array = d.get("players", [])
		if rows.is_empty():
			AUI.lbl(_list, "لا يوجد لاعبون" if term == "" else "لا نتائج", 18, AUI.TXT2)
		for p in rows:
			var pid := str(p["id"])
			var banned := int(p.get("banned", 0)) == 1
			var nm := str(p["name"]) if str(p["name"]) != "" else "لاعب " + pid.substr(0, 6)
			var c := AUI.card(_list)
			var hr := HBoxContainer.new()
			c.add_child(hr)
			var t := AUI.lbl(hr, nm, 24, AUI.BAD if banned else AUI.TXT)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if banned:
				AUI.lbl(hr, "محظور", 16, AUI.BAD)
			AUI.lbl(c, "%s    |    %s    |    v%s" % [str(p["game"]), str(p["platform"]), str(p["version"])], 15, AUI.TXT2, true)
			AUI.lbl(c, "آخر ظهور: %s    |    انضم: %s" % [AUI.when(int(p["last_seen"])), AUI.when(int(p["first_seen"]))], 14, AUI.TXT2, true)
			AUI.lbl(c, pid.substr(0, 12), 12, Color(1, 1, 1, 0.25))
			var br := HBoxContainer.new()
			br.add_theme_constant_override("separation", 8)
			c.add_child(br)
			var b1 := AUI.btn(br, "منح", func(): _grant_form(pid, nm), AUI.PANEL, 17, 44)
			b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b1.add_theme_color_override("font_color", AUI.GOLD)
			var b3 := AUI.btn(br, "رسالة", func(): _msg_form(pid, nm), AUI.PANEL, 17, 44)
			b3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b2 := AUI.btn(br, "رفع الحظر" if banned else "حظر", func(): _ban(pid, nm, banned), AUI.PANEL, 17, 44)
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if not banned:
				b2.add_theme_color_override("font_color", AUI.BAD))


func _ban(pid: String, nm: String, was_banned: bool) -> void:
	if was_banned:
		AModal.confirm(app, "رفع الحظر", "سيعود %s للعب بشكل طبيعي." % nm, "رفع الحظر",
			func(): Api.post_json("player/ban", {"player_id": pid, "banned": false}, func(_h, _d): refresh()), false)
	else:
		AModal.confirm(app, "حظر لاعب", "سيُمنع %s من استلام الأكواد والفعاليات وتظهر له رسالة حظر في اللعبة." % nm, "حظر",
			func(): Api.post_json("player/ban", {"player_id": pid, "banned": true, "reason": "admin"}, func(_h, _d): refresh()))


func _grant_form(pid: String, nm: String) -> void:
	var m := AModal.open(app, "منح هدية: " + nm)
	var v := m.content
	var coins := AUI.field(v, "عملات", "1000", true)
	var gems := AUI.field(v, "جواهر", "0", true)
	var note := AUI.field(v, "رسالة تظهر للاعب (اختياري)", "")
	var out := AUI.lbl(v, "", 20, AUI.OK, true)
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var busy := {"b": null, "on": false}
	busy["b"] = AUI.btn(v, "إرسال الهدية", func():
		if busy["on"]:
			return
		busy["on"] = true
		(busy["b"] as Button).disabled = true
		Api.post_json("player/grant", {"player_id": pid, "coins": int(coins.text), "gems": int(gems.text), "note": note.text}, func(_h: int, d: Dictionary):
			busy["on"] = false
			var bb: Variant = busy["b"]
			if bb != null and is_instance_valid(bb):
				(bb as Button).disabled = false
			if d.get("ok", false):
				app.say("ستصل الهدية عند فتح اللاعب للعبة")
				if is_instance_valid(m):
					m.close()
			elif is_instance_valid(out):
				out.text = "اكتب عملات أو جواهر"
				out.add_theme_color_override("font_color", AUI.BAD)), AUI.ACCENT, 22, 58)


func _msg_form(pid: String, nm: String) -> void:
	var m := AModal.open(app, "رسالة إلى " + nm)
	var v := m.content
	AUI.lbl(v, "تظهر للاعب مرة واحدة عند فتح اللعبة. ويرد عليك من صندوق الدعم.", 15, AUI.TXT2, true)
	var t := AUI.field(v, "الرسالة", "")
	var out := AUI.lbl(v, "", 18, AUI.BAD, true)
	var busy := {"on": false}
	AUI.btn(v, "إرسال", func():
		if t.text.strip_edges() == "" or busy["on"]:
			return
		busy["on"] = true
		Api.post_json("support/send", {"player_id": pid, "text": t.text.strip_edges()}, func(_h: int, d: Dictionary):
			busy["on"] = false
			if d.get("ok", false):
				app.say("تم الإرسال")
				if is_instance_valid(m):
					m.close()
			elif is_instance_valid(out):
				out.text = "فشل الإرسال"), AUI.ACCENT, 22, 56)
