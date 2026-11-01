# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name AAudit
extends VBoxContainer
## Log of everything done from the admin app (who, what, when).

var app: Node
var _list: VBoxContainer

const NAMES := {"player/ban": "حظر/رفع حظر", "player/grant": "منح هدية", "codes": "إنشاء أكواد", "code/toggle": "تفعيل/إيقاف كود", "code/delete": "حذف كود",
	"events": "نشر فعالية", "event/toggle": "تفعيل/إيقاف فعالية", "event/delete": "حذف فعالية", "announcements": "نشر إعلان", "announce/toggle": "تفعيل/إيقاف إعلان",
	"announce/delete": "حذف إعلان", "gamecfg": "تعديل إعدادات اللعبة", "support/send": "رد/رسالة للاعب", "score/hide": "إخفاء/إظهار من الصدارة",
	"key/create": "إنشاء مفتاح", "key/delete": "حذف مفتاح", "reports/clear": "مسح الأخطاء"}


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_list = AUI.scroll_page(self)


func refresh() -> void:
	Api.get_json("audit", func(code: int, d: Dictionary):
		if not is_instance_valid(_list):
			return
		for c in _list.get_children():
			c.queue_free()
		if code == 403:
			AUI.lbl(_list, "السجل للمالك فقط", 20, AUI.BAD)
			return
		if code != 200:
			AUI.lbl(_list, "تعذر الاتصال بالسيرفر", 20, AUI.BAD)
			return
		var rows: Array = d.get("audit", [])
		if rows.is_empty():
			AUI.lbl(_list, "السجل فارغ", 18, AUI.TXT2)
		for r in rows:
			var c := AUI.card(_list)
			var hr := HBoxContainer.new()
			c.add_child(hr)
			var a := AUI.lbl(hr, str(NAMES.get(str(r["action"]), str(r["action"]))), 19, AUI.TXT)
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			AUI.lbl(hr, str(r["who"]), 15, AUI.GOLD)
			AUI.lbl(c, AUI.when(int(r["ts"])), 13, AUI.TXT2)
			if str(r["detail"]) != "" and str(r["detail"]) != "{}":
				AUI.lbl(c, str(r["detail"]).substr(0, 120), 12, Color(1, 1, 1, 0.3), true))
