# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name AHome
extends VBoxContainer
## Home: money, players, codes, errors at a glance.

var app: Node
var _list: VBoxContainer


func _init() -> void:
	_list = AUI.scroll_page(self)


func refresh() -> void:
	Api.get_json("summary", func(code: int, s: Dictionary):
		for c in _list.get_children():
			c.queue_free()
		if code != 200:
			AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
			return
		if str(s.get("provider", "")) != "stripe":
			var w := AUI.card(_list, Color(0.83, 0.68, 0.36, 0.12))
			AUI.lbl(w, "وضع التجربة: الدفع غير حقيقي. لن تظهر أموال حقيقية قبل تفعيل بوابة الدفع.", 17, AUI.GOLD, true)
		var rev := AUI.card(_list)
		AUI.lbl(rev, "الأرباح (حقيقية)", 16, AUI.TXT2)
		AUI.lbl(rev, AUI.usd(float(s.get("revenue_usd", 0))), 44, AUI.GOLD)
		AUI.lbl(rev, "آخر 24 ساعة: %s     |     عمليات الدفع: %d" % [AUI.usd(float(s.get("revenue_24h_usd", 0))), int(s.get("paid_orders", 0))], 17, AUI.TXT2)
		if int(s.get("test_orders", 0)) > 0:
			AUI.lbl(rev, "عمليات تجريبية: %d (%s) - لا تُحسب" % [int(s["test_orders"]), AUI.usd(float(s.get("test_revenue_usd", 0)))], 15, AUI.TXT2)
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 10)
		g.add_theme_constant_override("v_separation", 10)
		_list.add_child(g)
		for it in [["اللاعبون", "players", AUI.TXT], ["نشطون (24س)", "active_24h", AUI.OK], ["أكواد فعّالة", "codes_active", AUI.TXT], ["مرات تفعيل الأكواد", "redemptions", AUI.TXT],
				["فعاليات جارية", "events_active", AUI.TXT], ["طلبات معلّقة", "pending_orders", AUI.GOLD], ["أخطاء (24س)", "errors_24h", AUI.BAD if int(s.get("errors_24h", 0)) > 0 else AUI.OK]]:
			var c := AUI.card(g)
			c.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
			AUI.lbl(c, it[0], 15, AUI.TXT2)
			AUI.lbl(c, str(int(s.get(it[1], 0))), 34, it[2]))
