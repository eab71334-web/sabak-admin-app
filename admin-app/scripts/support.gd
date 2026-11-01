# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name ASupport
extends VBoxContainer
## Support inbox: messages players send from inside the game; reply and they get it when they open the game.

var app: Node
var _list: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_list = AUI.scroll_page(self)


func refresh() -> void:
	Api.get_json("support", func(code: int, d: Dictionary):
		if not is_instance_valid(_list):
			return
		for c in _list.get_children():
			c.queue_free()
		if code != 200:
			AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
			return
		var rows: Array = d.get("threads", [])
		if rows.is_empty():
			AUI.lbl(_list, "لا توجد رسائل", 18, AUI.TXT2)
		for t in rows:
			var pid := str(t["player_id"])
			var nm := str(t["name"]) if str(t["name"]) != "" else "لاعب " + pid.substr(0, 6)
			var unread := int(t["unread"])
			var c := AUI.card(_list)
			var hr := HBoxContainer.new()
			c.add_child(hr)
			var n := AUI.lbl(hr, nm, 22, AUI.GOLD if unread > 0 else AUI.TXT)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if unread > 0:
				AUI.lbl(hr, "● %d جديدة" % unread, 15, AUI.BAD)
			AUI.lbl(c, ("أنت: " if int(t["from_admin"]) == 1 else "") + str(t["text"]), 16, AUI.TXT2, true)
			AUI.lbl(c, "%s    |    %s" % [AUI.when(int(t["ts"])), str(t["game"])], 13, AUI.TXT2)
			AUI.btn(c, "فتح المحادثة", func(): open_thread(pid, nm), AUI.PANEL, 17, 44))


func open_thread(pid: String, nm: String) -> void:
	var md := AModal.open(app, nm)
	var v := md.content
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	v.add_child(box)
	var load_msgs := func():
		Api.get_json("support/thread?player_id=" + pid.uri_encode(), func(_c: int, d: Dictionary):
			if not is_instance_valid(box):
				return
			for ch in box.get_children():
				ch.queue_free()
			for m in d.get("messages", []):
				var mine := int(m["from_admin"]) == 1
				var card := AUI.card(box, Color(0.83, 0.68, 0.36, 0.14) if mine else AUI.CARD)
				AUI.lbl(card, str(m["text"]), 18, AUI.TXT, true)
				AUI.lbl(card, ("أنت" if mine else nm) + "   " + AUI.when(int(m["ts"])) + ("   ✓" if mine and m["delivered_at"] != null else ""), 12, AUI.TXT2))
	load_msgs.call()
	var f := AUI.field(v, "ردّك", "")
	var busy := {"on": false}
	AUI.btn(v, "إرسال", func():
		var t := f.text.strip_edges()
		if t == "" or busy["on"]:
			return
		busy["on"] = true
		Api.post_json("support/send", {"player_id": pid, "text": t}, func(_h: int, d: Dictionary):
			busy["on"] = false
			if d.get("ok", false) and is_instance_valid(f):
				f.text = ""
				load_msgs.call()
				app.say("سيصل عند فتح اللاعب للعبة")), AUI.ACCENT, 22, 56)
