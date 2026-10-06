class_name Achievements
extends RefCounted
## Achievement definitions and checks. Unlocked keys live in Save.data.ach.

const LIST := [
	["first_job", "First Wheels", "Finish your first story chapter."],
	["act1", "New in Town", "Finish Act I."],
	["act2", "The Crew", "Finish Act II."],
	["act3", "Burned, Not Broken", "Survive Kane's ambush in Burned."],
	["story", "Legend of Solano Bay", "Finish the story."],
	["escape5", "Untouchable", "Escape a heat 5 pursuit."],
	["kane", "Kane's Nemesis", "Take down Lt. Kane."],
	["takedowns10", "Wrecking Ball", "Take down 10 police cars."],
	["races5", "Street Royalty", "Win 5 races."],
	["billboards", "Ad Blocker", "Smash all 20 billboards."],
	["drift50k", "Sideways", "Score 50,000 points in a drift zone."],
	["speed300", "Warp Speed", "Hit 300 km/h."],
	["speed450", "Ludicrous", "Hit 450 km/h."],
	["traps", "Camera Shy", "Set a record at all 6 speed traps."],
	["collector", "Collector", "Own every car."],
	["maxed", "Fully Built", "Max out every upgrade on one car."],
	["millionaire", "Millionaire", "Have $1,000,000 in the bank."],
]

static func has(key: String) -> bool:
	return Save.data.get("ach", []).has(key)

## Returns [title, desc] if newly unlocked, else [].
static func unlock(key: String) -> Array:
	var got: Array = Save.data.get("ach", [])
	if got.has(key):
		return []
	got.append(key)
	Save.data.ach = got
	Save.save_game()
	for a in LIST:
		if a[0] == key:
			return [a[1], a[2]]
	return []

## Periodic checks from saved stats and the player's car. Returns newly unlocked keys.
static func check(top_kmh: float) -> Array:
	var d: Dictionary = Save.data
	var want := []
	var c := int(d.contract)
	if c >= 1: want.append("first_job")
	if c >= 3: want.append("act1")
	if c >= 8: want.append("act2")
	if c >= 11: want.append("act3")
	if c >= 14: want.append("story")
	if int(d.get("cop_takedowns", 0)) >= 10: want.append("takedowns10")
	if int(d.races_won) >= 5: want.append("races5")
	if d.get("billboards", []).size() >= 20: want.append("billboards")
	var best: Dictionary = d.best
	for i in 3:
		if int(best.get("drift%d" % i, 0)) >= 50000:
			want.append("drift50k")
	if top_kmh >= 300.0: want.append("speed300")
	if top_kmh >= 450.0: want.append("speed450")
	var traps := 0
	for i in 6:
		if int(best.get("trap%d" % i, 0)) > 0:
			traps += 1
	if traps >= 6: want.append("traps")
	if d.owned.size() >= Data.CAR_ORDER.size(): want.append("collector")
	for id in d.upgrades:
		var up: Dictionary = d.upgrades[id]
		var full := true
		for k in Data.UPGRADES:
			if int(up.get(k, 0)) < Data.UPGRADES[k].cost.size():
				full = false
		if full:
			want.append("maxed")
	if int(d.cash) >= 1000000: want.append("millionaire")
	var out := []
	for k in want:
		if not has(k) and not out.has(k):
			out.append(k)
	return out
