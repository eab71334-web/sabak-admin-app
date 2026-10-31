# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
class_name DragScroll
extends ScrollContainer
## ScrollContainer that scrolls by dragging a finger anywhere inside it (also over buttons and text
## fields), like a normal phone list. A real tap still clicks; a drag never triggers the button under it.

const THRESH := 10.0
var _down := false
var _moved := 0.0
var _dragging := false
var _suppress_release := false   # swallow the mouse-release that the engine emulates after a touch drag


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # no white scrollbar; finger drag scrolls
	follow_focus = true


func _begin(pos: Vector2) -> void:
	_down = get_global_rect().has_point(pos)
	_moved = 0.0
	_dragging = false
	_suppress_release = false


func _end() -> void:
	if _down and _dragging:
		_suppress_release = true
		_handled()   # the finger moved: do not click what is under it
	_down = false
	_dragging = false


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.index != 0:
			return
		if st.pressed:
			_begin(st.position)
		else:
			_end()
	elif e is InputEventScreenDrag:
		var sd := e as InputEventScreenDrag
		if _down and sd.index == 0:
			_step(sd.relative.y)
	elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := e as InputEventMouseButton
		if mb.device == InputEvent.DEVICE_ID_EMULATION:
			if not mb.pressed and _suppress_release:
				_suppress_release = false
				_handled()
		elif mb.pressed:
			_begin(mb.position)
		else:
			_end()
	elif e is InputEventMouseMotion and _down:
		var mm := e as InputEventMouseMotion
		if mm.device == InputEvent.DEVICE_ID_EMULATION:
			if _dragging:
				_handled()   # emulated from a touch drag: already handled
		elif (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_step(mm.relative.y)


func _step(dy: float) -> void:
	_moved += absf(dy)
	if _moved < THRESH and not _dragging:
		return
	if not _dragging:
		_dragging = true
		_release()   # cancels the half-pressed button / text caret
	scroll_vertical -= int(dy)
	_handled()


func _handled() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func _release() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.gui_release_focus()
