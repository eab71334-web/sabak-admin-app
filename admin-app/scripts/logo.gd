# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name ALogo
extends Control
## The two overlapping rings of the Sabak icon (white + gold), drawn in code so it stays sharp at any size.


func _init(px := 44.0) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 0.0:
		return
	var r := s * 0.30
	var w := maxf(s * 0.045, 1.6)
	var c := size * 0.5
	draw_arc(c + Vector2(-r * 0.55, 0), r, 0, TAU, 64, Color(0.96, 0.96, 0.97), w, true)
	draw_arc(c + Vector2(r * 0.55, 0), r, 0, TAU, 64, AUI.ACCENT, w, true)
