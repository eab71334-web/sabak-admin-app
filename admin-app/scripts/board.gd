# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name ABoard
extends VBoxContainer
## Leaderboard moderation: top scores, hide a cheater from the in-game board (or show them again).

var app: Node
var _list: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_list = AUI.scroll_page(self)


func refresh() -> void:
	Api.get_json("scores?board=xp", func(code: int, d: Dictionary):
		if not is_instance_valid(_list):
			return
		for c in _list.get_children():
			c.queue_free()
		if code != 200:
			AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
			return
		var rows: Array = d.get("scores", [])
		if rows.is_empty():
			AUI.lbl(_list, "لا توجد نتائج بعد", 18, AUI.TXT2)
		var i := 0
		for r in rows:
			i += 1
			var hidden := int(r["hidden"]) == 1 or int(r["banned"]) == 1
			var c := AUI.card(_list)
			var hr := HBoxContainer.new()
			c.add_child(hr)
			var n := AUI.lbl(hr, "%d.  %s" % [i, str(r["name"]) if str(r["name"]) != "" else str(r["player_id"]).substr(0, 6)], 21, AUI.TXT2 if hidden else AUI.TXT)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			AUI.lbl(hr, "%d" % int(r["score"]), 24, AUI.GOLD)
			AUI.lbl(c, ("مخفي من اللوحة    |    " if hidden else "") + str(r["game"]), 13, AUI.BAD if hidden else AUI.TXT2)
			var g := str(r["game"])
			var pid := str(r["player_id"])
			var b := AUI.btn(c, "إظهار" if hidden else "إخفاء من اللوحة", func():
				Api.post_json("score/hide", {"game": g, "board": "xp", "player_id": pid, "hidden": not hidden}, func(_h, _d): refresh()), AUI.PANEL, 16, 42)
			if not hidden:
				b.add_theme_color_override("font_color", AUI.BAD))
