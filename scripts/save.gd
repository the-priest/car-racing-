extends Node
## Persistent career progress.

const PATH := "user://career.json"

var data := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_game()

func defaults() -> Dictionary:
	return {
		"cash": 8000, "rep": 0, "owned": ["vanta"], "car": "vanta", "upgrades": {}, "paint": {},
		"contract": 0, "contracts_done": [], "best": {}, "races_won": 0, "heat_escapes": 0,
		"pos": [], "hour": 19.0, "playtime": 0.0,
	}

func load_game() -> void:
	data = defaults()
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for k in parsed:
			data[k] = parsed[k]

func save_game() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func wipe() -> void:
	data = defaults()
	save_game()

func add_cash(n: int) -> void:
	data.cash = maxi(0, int(data.cash) + n)
