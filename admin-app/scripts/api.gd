# Copyright (c) 2026 Sabak Studios. All rights reserved. See LICENSE.
extends Node
## Talks to the Sabak backend admin API. Server address and admin key are kept on this device only.

const SAVE := "user://admin.json"

var url := ""
var key := ""
var game := ""          # "" = all games
var games: Array = []


func _ready() -> void:
	var f := FileAccess.open(SAVE, FileAccess.READ)
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			url = str(d.get("url", ""))
			key = str(d.get("key", ""))
			game = str(d.get("game", ""))
	var env := OS.get_environment("ADMIN_URL")
	if env != "":
		url = env
		key = OS.get_environment("ADMIN_KEY")


func save() -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"url": url, "key": key, "game": game}))


func logout() -> void:
	key = ""
	save()


## cb(http_code, dictionary); http_code 0 = could not connect
func call_api(method: int, path: String, body: Variant, cb: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, bytes: PackedByteArray):
		req.queue_free()
		var d: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		cb.call(code if result == HTTPRequest.RESULT_SUCCESS else 0, d if d is Dictionary else {}))
	var sep := "&" if path.contains("?") else "?"
	var full := url.rstrip("/") + "/admin/api/" + path + ((sep + "game=" + game.uri_encode()) if game != "" and method == HTTPClient.METHOD_GET else "")
	var err := req.request(full, PackedStringArray(["Content-Type: application/json", "X-Admin-Key: " + key]), method, JSON.stringify(body) if body != null else "")
	if err != OK:
		req.queue_free()
		cb.call(0, {})


func get_json(path: String, cb: Callable) -> void:
	call_api(HTTPClient.METHOD_GET, path, null, cb)


func post_json(path: String, body: Dictionary, cb: Callable) -> void:
	call_api(HTTPClient.METHOD_POST, path, body, cb)
