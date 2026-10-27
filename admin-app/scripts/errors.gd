# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name AErrors
extends VBoxContainer
## Errors: the most frequent problems first, then the latest reports.

var app: Node
var _list: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var b := AUI.btn(row, "مسح الأقدم من 7 أيام", func():
		Api.post_json("reports/clear", {"older_days": 7}, func(_h, _d):
			app.say("تم")
			refresh()), AUI.CARD, 17, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := AUI.btn(row, "مسح الكل", func():
		Api.post_json("reports/clear", {"older_days": 0}, func(_h, _d):
			app.say("تم")
			refresh()), AUI.CARD, 17, 46)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = AUI.scroll_page(self)


func refresh() -> void:
	Api.get_json("reports?limit=80", func(code: int, d: Dictionary):
		for c in _list.get_children():
			c.queue_free()
		if code != 200:
			AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
			return
		var top: Array = d.get("top", [])
		var rep: Array = d.get("reports", [])
		if top.is_empty() and rep.is_empty():
			AUI.lbl(_list, "لا توجد أخطاء. ممتاز!", 20, AUI.OK)
			return
		AUI.lbl(_list, "الأكثر تكراراً", 18, AUI.TXT2)
		for t in top:
			var c := AUI.card(_list)
			var hr := HBoxContainer.new()
			c.add_child(hr)
			var m := AUI.lbl(hr, str(t["message"]), 17, AUI.TXT, true)
			m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			AUI.lbl(hr, "×%d" % int(t["n"]), 26, AUI.BAD)
			AUI.lbl(c, "%d لاعب    |    آخر مرة %s    |    %s" % [int(t["players"]), AUI.when(int(t["last"])), str(t["game"])], 14, AUI.TXT2, true)
		AUI.lbl(_list, "آخر التقارير", 18, AUI.TXT2)
		for r in rep:
			var c := AUI.card(_list)
			var kc := AUI.BAD if str(r["kind"]) in ["error", "crash"] else AUI.GOLD
			AUI.lbl(c, "[%s]  %s" % [str(r["kind"]), str(r["message"])], 17, kc, true)
			AUI.lbl(c, "%s    |    %s %s    |    %s" % [AUI.when(int(r["ts"])), str(r["platform"]), str(r["version"]), str(r["game"])], 14, AUI.TXT2, true)
			if str(r["stack"]) != "":
				AUI.lbl(c, str(r["stack"]).substr(0, 400), 13, AUI.TXT2, true))
