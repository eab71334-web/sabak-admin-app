# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name ABars
extends Control
## Tiny 7-day bar chart (values above the bars, day labels below).

var vals: Array = []
var labels: Array = []
var color := AUI.ACCENT
var money := false


func _init(v: Array = [], l: Array = [], c := AUI.ACCENT, is_money := false) -> void:
	vals = v
	labels = l
	color = c
	money = is_money
	custom_minimum_size = Vector2(0, 130)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var n := vals.size()
	if n == 0:
		return
	var mx := 1.0
	for v in vals:
		mx = maxf(mx, float(v))
	var f := ThemeDB.fallback_font
	var w := size.x / n
	var area := size.y - 22.0 - 20.0
	for i in n:
		var v := float(vals[i])
		var h := area * v / mx
		var r := Rect2(i * w + w * 0.2, size.y - 22.0 - maxf(h, 3.0), w * 0.6, maxf(h, 3.0))
		var st := StyleBoxFlat.new()
		st.bg_color = Color(color.r, color.g, color.b, 0.9 if i == n - 1 else 0.5)
		st.set_corner_radius_all(6)
		draw_style_box(st, r)
		var txt := ("%.0f" % v) if not money else ("$%.0f" % v)
		draw_string(f, Vector2(i * w, r.position.y - 5.0), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 14, AUI.TXT)
		draw_string(f, Vector2(i * w, size.y - 5.0), str(labels[i]), HORIZONTAL_ALIGNMENT_CENTER, w, 12, AUI.TXT2)
