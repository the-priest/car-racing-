extends Node
## Persistent career progress.

const PATH := "user://career.json"

var data := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_game()

func defaults() -> Dictionary:
	return {
		"cash": 8000, "rep": 0, "owned": ["vanta"], "car": "vanta", "upgrades": {}, "paint": {}, "rims": {}, "glow": {},
		"contract": 0, "contracts_done": [], "best": {}, "races_won": 0, "heat_escapes": 0,
		"pos": [], "hour": 19.0, "playtime": 0.0,
	}

func load_game() -> void:
	data = defaults()
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for k in parsed:
			data[k] = parsed[k]

func save_game() -> void:
	# Write to a temp file then swap it in, so a crash mid-write can't corrupt the career.
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(tmp, PATH)

func wipe() -> void:
	data = defaults()
	save_game()

func add_cash(n: int) -> void:
	data.cash = maxi(0, int(data.cash) + n)
