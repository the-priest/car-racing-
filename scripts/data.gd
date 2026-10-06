class_name Data
extends RefCounted
## Static game data: car builds, paints, upgrades.

# Modern builds use the scanned-quality concept body; classics use procedural bodies.
const CARS := {
	"vanta": {"name": "Vanta GT", "tier": "D", "price": 0, "mass": 1420.0, "accel": 8.4, "top": 66.0, "grip": 13.2, "brake": 24.0, "nitro": 7.0, "awd": false, "drift": 1.0, "gears": 6, "cyl": 6, "idle": 850.0, "red": 7600.0, "paint": Color(0.55, 0.04, 0.06)},
	"stallion": {"name": "Stallion '69", "tier": "C", "price": 18000, "body": "stallion", "mass": 1550.0, "accel": 9.6, "top": 70.0, "grip": 12.8, "brake": 23.0, "nitro": 8.0, "awd": false, "drift": 1.35, "gears": 4, "cyl": 8, "idle": 700.0, "red": 6600.0, "paint": Color(0.05, 0.12, 0.45)},
	"wedge": {"name": "Wedge '78", "tier": "B", "price": 52000, "body": "wedge", "mass": 1420.0, "accel": 11.0, "top": 84.0, "grip": 15.2, "brake": 26.0, "nitro": 9.0, "awd": false, "drift": 1.2, "gears": 5, "cyl": 12, "idle": 950.0, "red": 8000.0, "paint": Color(0.9, 0.75, 0.05)},
	"stallion_hc": {"name": "Stallion Hellcat Restomod", "tier": "S", "price": 180000, "body": "stallion", "mass": 1600.0, "accel": 15.0, "top": 98.0, "grip": 17.0, "brake": 31.0, "nitro": 11.5, "awd": false, "drift": 1.4, "gears": 6, "cyl": 8, "idle": 800.0, "red": 7200.0, "paint": Color(0.02, 0.02, 0.025)},
	"vanta_s": {"name": "Vanta GT-S", "tier": "C", "price": 24000, "mass": 1400.0, "accel": 9.6, "top": 74.0, "grip": 14.4, "brake": 26.0, "nitro": 8.0, "awd": false, "drift": 1.1, "gears": 6, "cyl": 8, "idle": 750.0, "red": 7200.0, "paint": Color(0.05, 0.12, 0.55)},
	"vanta_r": {"name": "Vanta R", "tier": "B", "price": 60000, "mass": 1360.0, "accel": 11.0, "top": 82.0, "grip": 16.0, "brake": 28.0, "nitro": 9.0, "awd": false, "drift": 1.2, "gears": 7, "cyl": 8, "idle": 800.0, "red": 8200.0, "paint": Color(0.9, 0.9, 0.88)},
	"vanta_x": {"name": "Vanta X AWD", "tier": "A", "price": 120000, "mass": 1450.0, "accel": 12.8, "top": 92.0, "grip": 17.5, "brake": 30.0, "nitro": 10.0, "awd": true, "drift": 1.0, "gears": 7, "cyl": 10, "idle": 950.0, "red": 8700.0, "paint": Color(0.02, 0.02, 0.025)},
	"vanta_z": {"name": "Vanta Zero", "tier": "S", "price": 240000, "mass": 1380.0, "accel": 14.5, "top": 104.0, "grip": 19.0, "brake": 32.0, "nitro": 11.0, "awd": true, "drift": 1.05, "gears": 7, "cyl": 12, "idle": 1000.0, "red": 9200.0, "paint": Color(0.95, 0.42, 0.02)},
}
const DESC := {
	"vanta": "Your first ride. Balanced, forgiving and quietly quick.",
	"stallion": "'69 fastback with a big-block V8. Loves to go sideways.",
	"vanta_s": "Sharper GT-S tune: V8, stiffer chassis, more bite.",
	"wedge": "Late-70s V12 wedge. Pure poster-car drama.",
	"vanta_r": "Track-bred R spec. Lighter, louder, seven gears.",
	"vanta_x": "All-wheel-drive V10 missile. Grip for days.",
	"stallion_hc": "900 hp restomod muscle. Handle with respect.",
	"vanta_z": "The hypercar. V12, AWD, no apologies.",
}
## Story chapters you must finish before a tier can be bought.
const TIER_UNLOCK := {"D": 0, "C": 1, "B": 3, "A": 6, "S": 9}

static func unlocked(id: String, chapters_done: int) -> bool:
	return chapters_done >= int(TIER_UNLOCK.get(CARS[id].tier, 0))

const CAR_ORDER := ["vanta", "stallion", "vanta_s", "wedge", "vanta_r", "vanta_x", "stallion_hc", "vanta_z"]

const POLICE := {"name": "Interceptor", "tier": "-", "price": 0, "mass": 1500.0, "accel": 10.5, "top": 80.0, "grip": 15.5, "brake": 28.0, "nitro": 8.0, "awd": true, "drift": 0.9, "gears": 6, "cyl": 8, "idle": 800.0, "red": 7000.0, "paint": Color(0.03, 0.03, 0.035)}

## Rim finishes: [name, colour, metallic, roughness]; index 0 keeps the car's stock rims.
const RIMS := [["Stock", Color.WHITE, 0.0, 0.0], ["Chrome", Color(0.93, 0.93, 0.95), 1.0, 0.06], ["Gloss black", Color(0.03, 0.03, 0.035), 0.5, 0.2],
	["Gold", Color(0.85, 0.66, 0.24), 1.0, 0.14], ["Gunmetal", Color(0.24, 0.25, 0.27), 0.9, 0.25], ["Bronze", Color(0.55, 0.36, 0.2), 1.0, 0.2]]

const PAINTS := [
	Color(0.55, 0.04, 0.06), Color(0.85, 0.12, 0.02), Color(0.95, 0.42, 0.02), Color(0.9, 0.75, 0.05),
	Color(0.1, 0.5, 0.15), Color(0.02, 0.45, 0.45), Color(0.05, 0.12, 0.55), Color(0.3, 0.08, 0.5),
	Color(0.9, 0.9, 0.88), Color(0.45, 0.47, 0.5), Color(0.08, 0.08, 0.09), Color(0.02, 0.02, 0.025),
]

const UPGRADES := {
	"engine": {"name": "Engine", "cost": [6000, 14000, 28000, 52000, 90000]},
	"turbo": {"name": "Turbo / Supercharger", "cost": [9000, 22000, 45000, 80000]},
	"transmission": {"name": "Transmission", "cost": [7000, 18000, 38000]},
	"tires": {"name": "Tyres", "cost": [4000, 10000, 22000, 40000]},
	"suspension": {"name": "Suspension", "cost": [5000, 12000, 26000]},
	"brakes": {"name": "Brakes", "cost": [4000, 10000, 20000]},
	"nitro": {"name": "Nitrous", "cost": [5000, 12000, 25000, 45000]},
	"weight": {"name": "Weight Reduction", "cost": [8000, 20000, 42000]},
	"aero": {"name": "Aero Kit", "cost": [7000, 18000, 36000]},
}

## Applies upgrade levels. Fully built cars gain ~2x acceleration and ~45% top speed.
static func stats_for(id: String, up: Dictionary) -> Dictionary:
	var base: Dictionary = CARS.get(id, CARS.vanta).duplicate()
	var lv := func(k: String) -> float: return float(up.get(k, 0))
	var accel_mul: float = 1.0 + 0.10 * lv.call("engine") + 0.09 * lv.call("turbo") + 0.04 * lv.call("transmission")
	var top_mul: float = 1.0 + 0.04 * lv.call("engine") + 0.03 * lv.call("turbo") + 0.03 * lv.call("transmission") + 0.02 * lv.call("aero")
	var w: float = lv.call("weight")
	base.mass *= 1.0 - 0.05 * w
	accel_mul *= 1.0 + 0.05 * w
	base.accel *= accel_mul
	base.top *= top_mul
	base.grip *= (1.0 + 0.06 * lv.call("tires")) * (1.0 + 0.03 * lv.call("suspension"))
	base.brake *= 1.0 + 0.1 * lv.call("brakes")
	base.nitro *= 1.0 + 0.15 * lv.call("nitro")
	base["nitro_cap"] = 4.0 + lv.call("nitro") * 1.3
	base["downforce"] = 0.00011 * (1.0 + 0.45 * lv.call("aero"))
	base["shift_time"] = 0.15 - 0.03 * lv.call("transmission")
	base["turbo"] = lv.call("turbo") > 0
	base["aero_lvl"] = int(lv.call("aero"))
	return base

static func perf_index(s: Dictionary) -> int:
	return int(s.accel * 18 + s.top * 4 + s.grip * 12 + s.nitro * 5)
