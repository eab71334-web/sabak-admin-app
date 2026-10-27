# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name APayments
extends VBoxContainer
## Payments: who paid how much, and the biggest spenders.

var app: Node
var _list: VBoxContainer
var _mode := "orders"
var _tabs: HBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	add_child(_tabs)
	for t in [["orders", "كل العمليات"], ["spenders", "أكثر الدافعين"]]:
		var id: String = t[0]
		var b := AUI.btn(_tabs, t[1], func():
			_mode = id
			refresh(), AUI.CARD, 19, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = AUI.scroll_page(self)


func refresh() -> void:
	if _mode == "orders":
		Api.get_json("payments?limit=150", func(code: int, d: Dictionary):
			_clear()
			if code != 200:
				AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
				return
			var rows: Array = d.get("payments", [])
			if rows.is_empty():
				AUI.lbl(_list, "لا توجد عمليات دفع بعد", 18, AUI.TXT2)
			for p in rows:
				var c := AUI.card(_list)
				var hr := HBoxContainer.new()
				c.add_child(hr)
				var nm := str(p["name"]) if str(p["name"]) != "" else str(p["player_id"]).substr(0, 8)
				var t := AUI.lbl(hr, nm, 20, AUI.TXT)
				t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				AUI.lbl(hr, AUI.usd(float(p["price_usd"])), 24, AUI.GOLD)
				var st := str(p["status"])
				var stc := AUI.OK if st in ["paid", "granted"] else (AUI.GOLD if st == "created" else AUI.BAD)
				var stn: String = {"created": "بانتظار الدفع", "paid": "مدفوع - لم يُستلم بعد", "granted": "مدفوع وتم التسليم", "failed": "فشل", "refunded": "مُسترجع"}.get(st, st)
				AUI.lbl(c, "%s %d    |    %s" % [str(p["kind"]), int(p["amount"]), "تجريبي" if str(p["provider"]) == "test" else str(p["provider"])], 16, AUI.TXT2)
				AUI.lbl(c, stn + "    |    " + AUI.when(int(p["created_at"])) + ("    |    " + str(p["game"]) if str(p["game"]) != "" else ""), 15, stc, true))
	else:
		Api.get_json("spenders", func(code: int, d: Dictionary):
			_clear()
			if code != 200:
				AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
				return
			var rows: Array = d.get("spenders", [])
			if rows.is_empty():
				AUI.lbl(_list, "لا يوجد دافعون حقيقيون بعد", 18, AUI.TXT2)
			var rank := 1
			for p in rows:
				var c := AUI.card(_list)
				var hr := HBoxContainer.new()
				c.add_child(hr)
				var nm := str(p["name"]) if str(p["name"]) != "" else str(p["player_id"]).substr(0, 8)
				var t := AUI.lbl(hr, "%d.  %s" % [rank, nm], 21, AUI.TXT)
				t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				AUI.lbl(hr, AUI.usd(float(p["total"])), 26, AUI.GOLD)
				AUI.lbl(c, "%d عملية    |    آخر دفعة %s" % [int(p["n"]), AUI.when(int(p["last"]))], 15, AUI.TXT2)
				rank += 1)


func _clear() -> void:
	for c in _list.get_children():
		c.queue_free()
