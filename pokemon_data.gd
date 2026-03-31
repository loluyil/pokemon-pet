extends Node

var gen5_sets: Dictionary = {}
var gen5_pokemon: Dictionary = {}
var move_data: Dictionary = {}
var ability_data: Dictionary = {}
var type_chart: Dictionary = {}

const RECOVERY_MOVES = [
	"heal-order", "milk-drink", "moonlight", "morning-sun",
	"recover", "roost", "slack-off", "soft-boiled", "synthesis",
]

const PHYSICAL_SETUP = [
	"belly-drum", "bulk-up", "coil", "curse", "dragon-dance",
	"hone-claws", "howl", "meditate", "screech", "swords-dance",
]

const SPEED_SETUP = [
	"agility", "autotomize", "flame-charge", "rock-polish",
]

const SETUP = [
	"acid-armor", "agility", "autotomize", "belly-drum", "bulk-up",
	"calm-mind", "coil", "curse", "dragon-dance", "flame-charge",
	"growth", "hone-claws", "howl", "iron-defense", "meditate",
	"nasty-plot", "quiver-dance", "rain-dance", "rock-polish",
	"shell-smash", "shift-gear", "sunny-day", "swords-dance",
	"tail-glow", "work-up",
]

const NO_STAB = [
	"aqua-jet", "bullet-punch", "chatter", "clear-smog", "dragon-tail",
	"eruption", "explosion", "fake-out", "flame-charge", "future-sight",
	"ice-shard", "icy-wind", "incinerate", "knock-off", "mach-punch",
	"pluck", "pursuit", "quick-attack", "rapid-spin", "reversal",
	"self-destruct", "shadow-sneak", "sky-attack", "sky-drop", "snarl",
	"sucker-punch", "u-turn", "vacuum-wave", "volt-switch", "water-spout",
]

const HAZARDS = ["spikes", "stealth-rock", "toxic-spikes"]
const PIVOT_MOVES = ["u-turn", "volt-switch"]

const MOVE_PAIRS = [
	["light-screen", "reflect"],
	["sleep-talk", "rest"],
	["protect", "wish"],
	["leech-seed", "substitute"],
]

const PRIORITY_POKEMON = [
	"bisharp", "breloom", "cacturne", "dusknoir",
	"honchkrow", "scizor", "shedinja", "shiftry",
]

const NFE_POKEMON = [
	"chansey", "dusclops", "gligar", "murkrow",
	"pikachu", "porygon2", "rhydon", "scyther",
]

var status_moves: Array = []

func _ready():
	load_data()
	build_status_move_cache()

func load_data():
	gen5_sets = load_json("res://data/gen5sets.json")
	gen5_pokemon = load_json("res://data/gen5pokemon.json")
	move_data = load_json("res://data/moves.json")
	ability_data = load_json("res://data/abilities.json")
	type_chart = load_json("res://data/type_chart.json")

func load_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	return data

func build_status_move_cache():
	for move_name in move_data:
		if move_data[move_name]["category"] == "status" and move_name != "nature-power":
			status_moves.append(move_name)

func random_team() -> Array:
	var pokemon: Array = []
	var base_formes: Dictionary = {}
	var type_count: Dictionary = {}
	var type_weaknesses: Dictionary = {}
	var type_double_weaknesses: Dictionary = {}
	var team_details: Dictionary = {}
	var num_max_level: int = 0
	
	var pokemon_pool = gen5_sets.keys().duplicate()
	pokemon_pool.shuffle()
	
	var pool_index = 0
	while pool_index < pokemon_pool.size() and pokemon.size() < 6:
		var species_name = pokemon_pool[pool_index]
		pool_index += 1
		
		if not gen5_pokemon.has(species_name):
			continue
		
		var base_species = species_name.split("-")[0] if "-" in species_name else species_name
		
		# Species Clause
		if base_formes.has(base_species):
			continue
		
		# Zoroark shouldn't be in the last slot
		if species_name == "zoroark" and pokemon.size() >= 5:
			continue
		
		var species_data = gen5_pokemon[species_name]
		var types = species_data["types"]
		
		# --- Type and weakness limits ---
		var skip = false
		
		# Limit two of any type
		for type_name in types:
			if type_count.get(type_name, 0) >= 2:
				skip = true
				break
		if skip:
			continue
		
		# Limit three weak to any type, one double weak
		for atk_type in type_chart.keys():
			var eff = get_defensive_effectiveness(atk_type, types)
			if eff > 1.0:
				if type_weaknesses.get(atk_type, 0) >= 3:
					skip = true
					break
			if eff >= 4.0:
				if type_double_weaknesses.get(atk_type, 0) >= 1:
					skip = true
					break
		if skip:
			continue
		
		# Dry Skin counts as Fire weakness
		var has_dry_skin = false
		for s in gen5_sets[species_name]["sets"]:
			if "dry-skin" in s["abilities"]:
				has_dry_skin = true
				break
		if has_dry_skin and get_defensive_effectiveness("fire", types) == 1.0:
			if type_weaknesses.get("fire", 0) >= 3:
				continue
		
		# Limit one level 100 pokemon
		var level = gen5_sets[species_name]["level"]
		if level >= 100 and num_max_level >= 1:
			continue
		
		# Check compatibility
		if not get_pokemon_compatibility(species_name, pokemon):
			continue
		
		var mon_set = random_set(species_name, team_details, pokemon.size() == 0)
		pokemon.append(mon_set)
		
		if pokemon.size() >= 6:
			break
		
		base_formes[base_species] = true
		
		for type_name in types:
			type_count[type_name] = type_count.get(type_name, 0) + 1
		
		for atk_type in type_chart.keys():
			var eff = get_defensive_effectiveness(atk_type, types)
			if eff > 1.0:
				type_weaknesses[atk_type] = type_weaknesses.get(atk_type, 0) + 1
			if eff >= 4.0:
				type_double_weaknesses[atk_type] = type_double_weaknesses.get(atk_type, 0) + 1
		
		if mon_set["ability"] == "dry-skin" and get_defensive_effectiveness("fire", types) == 1.0:
			type_weaknesses["fire"] = type_weaknesses.get("fire", 0) + 1
		
		if level >= 100:
			num_max_level += 1
		
		update_team_details(team_details, mon_set)
	
	return pokemon

func update_team_details(team_details: Dictionary, mon: Dictionary):
	var ability = mon["ability"]
	var move_names: Array = mon["move_names"]
	
	if ability == "snow-warning" or "hail" in move_names:
		team_details["hail"] = 1
	if ability == "drizzle" or "rain-dance" in move_names:
		team_details["rain"] = 1
	if ability == "sand-stream":
		team_details["sand"] = 1
	if ability == "drought" or "sunny-day" in move_names:
		team_details["sun"] = 1
	if "aromatherapy" in move_names or "heal-bell" in move_names:
		team_details["status_cure"] = 1
	if "spikes" in move_names:
		team_details["spikes"] = team_details.get("spikes", 0) + 1
	if "stealth-rock" in move_names:
		team_details["stealth_rock"] = 1
	if "toxic-spikes" in move_names:
		team_details["toxic_spikes"] = 1
	if "rapid-spin" in move_names:
		team_details["rapid_spin"] = 1
	if "reflect" in move_names and "light-screen" in move_names:
		team_details["screens"] = 1

func get_pokemon_compatibility(species_name: String, pokemon: Array) -> bool:
	var incompatible_pairs = [
		[["blissey", "chansey"], ["blissey", "chansey"]],
		[["illumise"], ["volbeat"]],
		[["parasect", "jynx", "toxicroak"], ["ninetales", "groudon"]],
		[["shedinja"], ["tyranitar", "hippowdon", "abomasnow"]],
	]
	
	for pair in incompatible_pairs:
		var group_a: Array = pair[0]
		var group_b: Array = pair[1]
		if species_name in group_b:
			for mon in pokemon:
				if mon["name"] in group_a:
					return false
		if species_name in group_a:
			for mon in pokemon:
				if mon["name"] in group_b:
					return false
	
	return true

func random_set(species_name: String, team_details: Dictionary, is_lead: bool) -> Dictionary:
	var species_data = gen5_pokemon[species_name]
	var set_info = gen5_sets[species_name]
	var types = species_data["types"]
	
	# Handle type overrides (Arceus forms)
	if set_info.has("type_override"):
		types = set_info["type_override"]
	
	var level = set_info["level"]
	var sets = set_info["sets"]
	
	# --- Pick a set (enforce Spinner if team needs one) ---
	var possible_sets = []
	var can_spinner = false
	for s in sets:
		if not team_details.get("rapid_spin", false) and s["role"] == "Spinner":
			can_spinner = true
	
	for s in sets:
		if team_details.get("rapid_spin", false) and s["role"] == "Spinner":
			continue
		if can_spinner and s["role"] != "Spinner":
			continue
		possible_sets.append(s)
	
	if possible_sets.is_empty():
		possible_sets = sets.duplicate()
	
	var chosen_set = possible_sets.pick_random()
	var role: String = chosen_set["role"]
	var move_pool: Array = chosen_set["movepool"].duplicate()
	var abilities: Array = chosen_set["abilities"].duplicate()
	var preferred_type: String = ""
	if chosen_set.has("preferredTypes"):
		var pref_types: Array = chosen_set["preferredTypes"]
		preferred_type = pref_types.pick_random()
	
	var moves: Array = random_moveset(types, abilities, team_details, species_name, is_lead, move_pool, preferred_type, role)
	var counter = build_move_counter(moves, types, preferred_type, abilities)
	var ability = get_ability(types, moves, abilities, counter, team_details, species_name, preferred_type, role)
	var item = get_priority_item(ability, types, moves, counter, team_details, species_name, is_lead, preferred_type, role)
	if item == "":
		item = get_item(ability, types, moves, counter, team_details, species_name, is_lead, preferred_type, role)
	
	if item == "Leftovers" and "poison" in types:
		item = "Black Sludge"
	
	# --- Determine EVs/IVs
	var ivs = {"hp": 31, "atk": 31, "def": 31, "spa": 31, "spd": 31, "spe": 31}
	var evs = {"hp": 85, "atk": 85, "def": 85, "spa": 85, "spd": 85, "spe": 85}
	
	# Minimize attack for special attackers
	if counter["physical"] == 0 or (counter["physical"] <= 1 and has_move(moves, "foul-play")):
		evs["atk"] = 0
		ivs["atk"] = 0
	
	# Minimize speed for Trick Room / Gyro Ball
	if has_move(moves, "gyro-ball") or has_move(moves, "metal-burst") or has_move(moves, "trick-room"):
		evs["spe"] = 0
		ivs["spe"] = 0
	
	# Optimize HP EVs for Stealth Rock
	evs["hp"] = optimize_hp_ev(species_data["hp"], ivs["hp"], evs["hp"], level, ability, moves, item, types)
	
	# Build moveset @gen5sets.json
	var moveset: Array = []
	for move_name in moves:
		var details = get_move_details(move_name)
		details["name"] = move_name
		var max_pp := _default_max_pp(details.get("power", 0), details.get("category", "status"))
		details["current_pp"] = max_pp
		details["max_pp"]     = max_pp
		moveset.append(details)
	moveset.shuffle()
	
	return {
		"name": species_name,
		"level": level,
		"types": types,
		"ability": ability,
		"item": item,
		"role": role,
		"base_hp": species_data["hp"],
		"base_attack": species_data["attack"],
		"base_defense": species_data["defense"],
		"base_sp_atk": species_data["sp_atk"],
		"base_sp_def": species_data["sp_def"],
		"base_speed": species_data["speed"],
		"ivs": ivs,
		"evs": evs,
		"moveset": moveset,
		"move_names": moves,
	}

func random_moveset(types: Array, abilities: Array, team_details: Dictionary,
	species_name: String, is_lead: bool, move_pool: Array,
	preferred_type: String, role: String) -> Array:
	
	var moves: Array = []
	var counter = build_move_counter(moves, types, preferred_type, abilities)
	
	cull_move_pool(types, moves, abilities, counter, move_pool, team_details, species_name, is_lead, preferred_type, role)
	
	if move_pool.size() <= 4:
		while move_pool.size() > 0:
			var idx = randi() % move_pool.size()
			var moveid = move_pool[idx]
			moves.append(moveid)
			move_pool.remove_at(idx)
		return moves
	
	# Competitive Pokemon recommended moves
	
	if "facade" in move_pool and "guts" in abilities:
		add_move("facade", moves, move_pool)
	
	for moveid in ["seismic-toss", "spore"]:
		if moveid in move_pool:
			add_move(moveid, moves, move_pool)
	
	if "thunder-wave" in move_pool and "prankster" in abilities:
		add_move("thunder-wave", moves, move_pool)
	
	if "stealth-rock" in move_pool and not team_details.get("stealth_rock", false):
		add_move("stealth-rock", moves, move_pool)
	
	if role in ["Bulky Support", "Spinner"] and not team_details.get("rapid_spin", false):
		if "rapid-spin" in move_pool:
			add_move("rapid-spin", moves, move_pool)
	
	# STAB priority for Bulky Attacker, Bulky Setup, and priority pokemon
	if role in ["Bulky Attacker", "Bulky Setup"] or species_name in PRIORITY_POKEMON:
		var priority_moves = []
		for moveid in move_pool:
			var mdata = get_move_details(moveid)
			var move_type = get_move_type(moveid, types, abilities, preferred_type)
			if move_type in types and mdata["priority"] > 0 and mdata["power"] > 0:
				priority_moves.append(moveid)
		if priority_moves.size() > 0:
			add_move(priority_moves.pick_random(), moves, move_pool)
	
	# Enforce STAB
	for type in types:
		while run_enforcement_checker(type, move_pool, moves, abilities, types, counter, species_name):
			var stab_moves = get_stab_moves(move_pool, type, types, abilities, preferred_type)
			if stab_moves.is_empty():
				break
			var pick = stab_moves.pick_random()
			add_move(pick, moves, move_pool)
			counter = build_move_counter(moves, types, preferred_type, abilities)
	
	# Enforce preferred type
	counter = build_move_counter(moves, types, preferred_type, abilities)
	if preferred_type != "" and counter.get("preferred", 0) == 0:
		var stab_moves = get_stab_moves(move_pool, preferred_type, types, abilities, preferred_type)
		if stab_moves.size() > 0:
			add_move(stab_moves.pick_random(), moves, move_pool)
	
	# If no STAB move was added
	counter = build_move_counter(moves, types, preferred_type, abilities)
	if counter.get("stab", 0) == 0:
		var stab_moves = []
		for moveid in move_pool:
			var mdata = get_move_details(moveid)
			var move_type = get_move_type(moveid, types, abilities, preferred_type)
			if moveid not in NO_STAB and mdata["power"] > 0 and move_type in types:
				stab_moves.append(moveid)
		if stab_moves.size() > 0:
			add_move(stab_moves.pick_random(), moves, move_pool)
		elif "u-turn" in move_pool and "bug" in types:
			add_move("u-turn", moves, move_pool)
	
	# Enforce recovery for bulky roles
	if role in ["Bulky Support", "Bulky Attacker", "Bulky Setup", "Spinner", "Staller"]:
		var recovery = move_pool.filter(func(m): return m in RECOVERY_MOVES)
		if recovery.size() > 0:
			add_move(recovery.pick_random(), moves, move_pool)
	
	# Enforce Staller moves
	if role == "Staller":
		for moveid in ["protect", "toxic"]:
			if moveid in move_pool and moves.size() < 4:
				add_move(moveid, moves, move_pool)
	
	# Enforce setup
	if "Setup" in role:
		var non_speed = move_pool.filter(func(m): return m in SETUP and m not in SPEED_SETUP)
		if non_speed.size() > 0:
			add_move(non_speed.pick_random(), moves, move_pool)
		else:
			var setup_moves = move_pool.filter(func(m): return m in SETUP)
			if setup_moves.size() > 0:
				add_move(setup_moves.pick_random(), moves, move_pool)
	
	# Enforce at least one damaging move
	counter = build_move_counter(moves, types, preferred_type, abilities)
	if counter.get("damaging", 0) == 0 and not (has_move(moves, "u-turn") and "bug" in types):
		var attacking = []
		for moveid in move_pool:
			var mdata = get_move_details(moveid)
			if moveid not in NO_STAB and mdata["category"] != "status":
				attacking.append(moveid)
		if attacking.size() > 0:
			add_move(attacking.pick_random(), moves, move_pool)
	
	# Enforce coverage for attackers
	counter = build_move_counter(moves, types, preferred_type, abilities)
	if role in ["Fast Attacker", "Setup Sweeper", "Bulky Attacker", "Wallbreaker"]:
		if counter.get("damaging", 0) == 1:
			var current_type = ""
			for m in moves:
				var mdata = get_move_details(m)
				if mdata["category"] != "status" and mdata["power"] > 0:
					current_type = get_move_type(m, types, abilities, preferred_type)
					break
			var coverage = []
			for moveid in move_pool:
				var mdata = get_move_details(moveid)
				var move_type = get_move_type(moveid, types, abilities, preferred_type)
				if moveid not in NO_STAB and mdata["power"] > 0 and move_type != current_type:
					coverage.append(moveid)
			if coverage.size() > 0:
				add_move(coverage.pick_random(), moves, move_pool)
	
	# Fill remaining slots randomly, respecting move pairs
	while moves.size() < 4 and move_pool.size() > 0:
		var idx = randi() % move_pool.size()
		var moveid = move_pool[idx]
		add_move(moveid, moves, move_pool)
		
		for pair in MOVE_PAIRS:
			if moveid == pair[0] and pair[1] in move_pool and moves.size() < 4:
				add_move(pair[1], moves, move_pool)
			if moveid == pair[1] and pair[0] in move_pool and moves.size() < 4:
				add_move(pair[0], moves, move_pool)
	
	return moves

func cull_move_pool(types: Array, moves: Array, abilities: Array,
	counter: Dictionary, move_pool: Array, team_details: Dictionary,
	species_name: String, is_lead: bool, preferred_type: String, role: String):
	
	# Remove duplicate Hidden Powers
	var has_hp = false
	for m in moves:
		if m.begins_with("hidden-power-"):
			has_hp = true
	if has_hp:
		var to_remove = []
		for m in move_pool:
			if m.begins_with("hidden-power-"):
				to_remove.append(m)
		for m in to_remove:
			move_pool.erase(m)
	
	if moves.size() + move_pool.size() <= 4:
		return
	
	# If two slots left and only one unpaired move, remove it
	if moves.size() == 2:
		var unpaired = move_pool.duplicate()
		for pair in MOVE_PAIRS:
			if pair[0] in move_pool and pair[1] in move_pool:
				unpaired.erase(pair[0])
				unpaired.erase(pair[1])
		if unpaired.size() == 1:
			move_pool.erase(unpaired[0])
	
	# If one slot left, remove incomplete pairs
	if moves.size() == 3:
		for pair in MOVE_PAIRS:
			if pair[0] in move_pool and pair[1] in move_pool:
				move_pool.erase(pair[0])
				move_pool.erase(pair[1])
	
	if team_details.get("screens", false) and move_pool.size() >= 6:
		move_pool.erase("reflect")
		move_pool.erase("light-screen")
	if moves.size() + move_pool.size() <= 4:
		return
	
	if team_details.get("stealth_rock", false):
		move_pool.erase("stealth-rock")
	if moves.size() + move_pool.size() <= 4:
		return
	
	if team_details.get("rapid_spin", false):
		move_pool.erase("rapid-spin")
	if moves.size() + move_pool.size() <= 4:
		return
	
	if team_details.get("toxic_spikes", false):
		move_pool.erase("toxic-spikes")
	if moves.size() + move_pool.size() <= 4:
		return
	
	if team_details.get("spikes", 0) >= 2:
		move_pool.erase("spikes")
	if moves.size() + move_pool.size() <= 4:
		return
	
	if team_details.get("status_cure", false):
		move_pool.erase("aromatherapy")
		move_pool.erase("heal-bell")
	if moves.size() + move_pool.size() <= 4:
		return

	var bad_with_setup = ["heal-bell", "pursuit", "toxic"]
	
	incompatible_moves(moves, move_pool, status_moves, ["healing-wish", "switcheroo", "trick"])
	incompatible_moves(moves, move_pool, SETUP, PIVOT_MOVES)
	incompatible_moves(moves, move_pool, SETUP, HAZARDS)
	incompatible_moves(moves, move_pool, SETUP, bad_with_setup)
	incompatible_moves(moves, move_pool, PHYSICAL_SETUP, PHYSICAL_SETUP)
	incompatible_moves(moves, move_pool, ["fake-out", "u-turn"], ["switcheroo", "trick"])
	incompatible_moves(moves, move_pool, ["substitute"], PIVOT_MOVES)
	incompatible_moves(moves, move_pool, ["rest"], ["substitute"])
	
	# Redundant attacks
	incompatible_moves(moves, move_pool, ["psychic"], ["psyshock"])
	incompatible_moves(moves, move_pool, ["scald", "surf"], ["hydro-pump"])
	incompatible_moves(moves, move_pool, ["body-slam", "return"], ["body-slam", "double-edge"])
	incompatible_moves(moves, move_pool, ["giga-drain", "leaf-storm"], ["leaf-storm", "petal-dance", "power-whip"])
	incompatible_moves(moves, move_pool, ["drain-punch", "focus-blast"], ["close-combat", "high-jump-kick", "superpower"])
	incompatible_moves(moves, move_pool, ["payback"], ["pursuit"])
	incompatible_moves(moves, move_pool, ["wild-charge"], ["thunderbolt"])
	incompatible_moves(moves, move_pool, ["flamethrower"], ["overheat"])
	incompatible_moves(moves, move_pool, ["leech-seed"], ["dragon-tail"])
	incompatible_moves(moves, move_pool, ["fiery-dance", "lava-plume"], ["fire-blast"])
	incompatible_moves(moves, move_pool, ["encore"], ["roar"])
	incompatible_moves(moves, move_pool, ["moonlight"], ["rock-polish"])
	incompatible_moves(moves, move_pool, ["memento"], ["whirlwind"])
	incompatible_moves(moves, move_pool, ["switcheroo"], ["sucker-punch"])
	incompatible_moves(moves, move_pool, ["body-slam"], ["healing-wish"])
	
	if species_name == "dugtrio":
		incompatible_moves(moves, move_pool, status_moves, ["memento"])
	
	var status_inflicting = ["stun-spore", "thunder-wave", "toxic", "will-o-wisp", "yawn"]
	if "prankster" not in abilities and role != "Staller":
		incompatible_moves(moves, move_pool, status_inflicting, status_inflicting)
	
	if "guts" in abilities:
		incompatible_moves(moves, move_pool, ["protect"], ["swords-dance"])
	
	if species_name == "mamoswine":
		incompatible_moves(moves, move_pool, ["stealth-rock", "stone-edge"], ["stone-edge", "superpower"])

func incompatible_moves(moves: Array, move_pool: Array, list_a, list_b):
	var arr_a = list_a if list_a is Array else [list_a]
	var arr_b = list_b if list_b is Array else [list_b]
	
	var has_a = false
	var has_b = false
	for m in moves:
		if m in arr_a:
			has_a = true
		if m in arr_b:
			has_b = true
	
	if has_a:
		for m in arr_b:
			move_pool.erase(m)
	if has_b:
		for m in arr_a:
			move_pool.erase(m)
	
	var pool_a = move_pool.filter(func(m): return m in arr_a)
	var pool_b = move_pool.filter(func(m): return m in arr_b)
	if pool_a.size() > 0 and pool_b.size() > 0:
		var to_remove = pool_b if pool_a.size() >= pool_b.size() else pool_a
		for m in to_remove:
			move_pool.erase(m)

func get_ability(types: Array, moves: Array, abilities: Array,
	counter: Dictionary, team_details: Dictionary,
	species_name: String, preferred_type: String, role: String) -> String:
	
	if abilities.size() <= 1:
		return abilities[0]
	
	if species_name == "marowak" and counter.get("recoil", 0) > 0:
		return "rock-head"
	if species_name == "kingler" and counter.get("sheerforce", 0) > 0:
		return "sheer-force"
	if species_name == "golduck" and team_details.get("rain", false):
		return "swift-swim"
	
	var allowed: Array = []
	for ability in abilities:
		if not should_cull_ability(ability, types, moves, abilities, counter, team_details, species_name, role):
			allowed.append(ability)
	
	if allowed.size() >= 1:
		return allowed.pick_random()
	
	var weather_abilities = ["chlorophyll", "hydration", "sand-force", "sand-rush", "solar-power", "swift-swim"]
	var weather_found = abilities.filter(func(a): return a in weather_abilities)
	if weather_found.size() > 0:
		return weather_found.pick_random()
	
	return abilities.pick_random()

func should_cull_ability(ability: String, types: Array, moves: Array,
	abilities: Array, counter: Dictionary,
	team_details: Dictionary, species_name: String, role: String) -> bool:
	
	match ability:
		"chlorophyll", "solar-power":
			return not team_details.get("sun", false)
		"hydration", "swift-swim":
			return not team_details.get("rain", false)
		"iron-fist":
			return counter.get("ironfist", 0) == 0
		"sheer-force":
			return counter.get("sheerforce", 0) == 0
		"overgrow":
			return counter.get("grass", 0) == 0
		"rock-head":
			return counter.get("recoil", 0) == 0
		"sand-force", "sand-rush":
			return not team_details.get("sand", false)
	
	return false

func get_priority_item(ability: String, types: Array, moves: Array,
	counter: Dictionary, team_details: Dictionary,
	species_name: String, is_lead: bool, preferred_type: String, role: String) -> String:
	
	if species_name == "farfetchd":
		return "Stick"
	if species_name in ["latias", "latios"]:
		return "Soul Dew"
	if species_name == "marowak":
		return "Thick Club"
	if species_name == "pikachu":
		return "Light Ball"
	if species_name in ["shedinja", "smeargle"]:
		return "Focus Sash"
	if species_name == "unown":
		return "Choice Specs"
	if species_name == "wobbuffet":
		return "Custap Berry"
	if ability == "harvest":
		return "Sitrus Berry"
	if species_name == "ditto":
		return "Choice Scarf"
	if species_name == "honchkrow":
		return "Life Orb"
	if species_name == "exploud" and role == "Bulky Attacker":
		return "Choice Band"
	if ability == "poison-heal" or (has_move(moves, "facade") and species_name != "stoutland"):
		return "Toxic Orb"
	if ability == "speed-boost" and species_name != "ninjask":
		return "Life Orb"
	if species_name in NFE_POKEMON:
		return "Eviolite"
	if has_move(moves, "healing-wish") or has_move(moves, "memento") or has_move(moves, "switcheroo") or has_move(moves, "trick"):
		var base_speed = gen5_pokemon[species_name]["speed"]
		if base_speed >= 60 and base_speed <= 108 and role != "Wallbreaker" and counter.get("priority", 0) == 0:
			return "Choice Scarf"
		else:
			if counter.get("physical", 0) > counter.get("special", 0):
				return "Choice Band"
			else:
				return "Choice Specs"
	if has_move(moves, "belly-drum"):
		return "Sitrus Berry"
	if has_move(moves, "water-spout"):
		return "Choice Scarf"
	if has_move(moves, "shell-smash"):
		return "White Herb"
	if has_move(moves, "psycho-shift"):
		return "Flame Orb"
	if ability == "magic-guard":
		if has_move(moves, "counter"):
			return "Focus Sash"
		return "Life Orb"
	if species_name == "rampardos" and role == "Fast Attacker":
		return "Choice Scarf"
	if ability == "sheer-force" and counter.get("sheerforce", 0) > 0:
		return "Life Orb"
	if has_move(moves, "acrobatics"):
		return "Flying Gem"
	if species_name == "hitmonlee" and ability == "unburden":
		if has_move(moves, "fake-out"):
			return "Normal Gem"
		return "Fighting Gem"
	if has_move(moves, "light-screen") and has_move(moves, "reflect"):
		return "Light Clay"
	if has_move(moves, "rest") and not has_move(moves, "sleep-talk"):
		if ability not in ["natural-cure", "shed-skin"]:
			if has_move(moves, "rain-dance") and ability == "hydration":
				return "Damp Rock"
			return "Chesto Berry"
	if role == "Staller":
		return "Leftovers"
	
	return ""

func get_item(ability: String, types: Array, moves: Array,
	counter: Dictionary, team_details: Dictionary,
	species_name: String, is_lead: bool, preferred_type: String, role: String) -> String:
	
	var base_stats = gen5_pokemon[species_name]
	var def_total = base_stats["hp"] + base_stats["defense"] + base_stats["sp_def"]
	var base_speed = base_stats["speed"]
	var base_atk = base_stats["attack"]
	var base_spa = base_stats["sp_atk"]
	
	var scarf_reqs = (
		role != "Wallbreaker" and
		base_speed >= 60 and base_speed <= 108 and
		counter.get("priority", 0) == 0 and not has_move(moves, "pursuit")
	)
	
	if has_move(moves, "pursuit") and has_move(moves, "sucker-punch") and counter.get("dark", 0) > 0:
		if species_name not in PRIORITY_POKEMON or counter.get("dark", 0) >= 2:
			return "Black Glasses"
	
	if counter.get("special", 0) == 4:
		if scarf_reqs and base_spa >= 90 and randi() % 2 == 0:
			return "Choice Scarf"
		return "Choice Specs"
	
	if counter.get("special", 0) == 3 and has_move(moves, "u-turn"):
		return "Choice Specs"
	
	if counter.get("physical", 0) == 4 and species_name not in ["jirachi", "spinda"]:
		if not has_move(moves, "dragon-tail") and not has_move(moves, "fake-out") and not has_move(moves, "rapid-spin"):
			if scarf_reqs and (base_atk >= 100 or ability in ["pure-power", "huge-power"]) and randi() % 2 == 0:
				return "Choice Scarf"
			return "Choice Band"
	
	if ability == "sturdy" and has_move(moves, "explosion"):
		return "Custap Berry"
	if "normal" in types and has_move(moves, "fake-out") and counter.get("normal", 0) > 0:
		return "Silk Scarf"
	if species_name == "palkia":
		return "Lustrous Orb"
	if has_move(moves, "outrage") and counter.get("setup", 0) > 0:
		return "Lum Berry"
	
	if ability == "rough-skin":
		return "Rocky Helmet"
	if species_name != "ho-oh" and role != "Wallbreaker" and ability == "regenerator":
		if base_stats["hp"] + base_stats["defense"] >= 180 and randi() % 2 == 0:
			return "Rocky Helmet"
	
	if has_move(moves, "protect") or has_move(moves, "substitute"):
		return "Leftovers"
	
	var ground_eff = get_defensive_effectiveness("ground", types)
	if ground_eff >= 4.0 and ability != "levitate":
		return "Air Balloon"
	
	if role == "Fast Support" and is_lead and def_total < 255:
		if counter.get("recovery", 0) == 0 and (counter.get("hazards", 0) > 0 or counter.get("setup", 0) > 0):
			if counter.get("recoil", 0) == 0 or ability == "rock-head":
				return "Focus Sash"
	
	if role == "Fast Support":
		if counter.get("physical", 0) + counter.get("special", 0) >= 3:
			if not has_move(moves, "rapid-spin") and not has_move(moves, "u-turn") and not has_move(moves, "volt-switch"):
				var rock_eff = get_defensive_effectiveness("rock", types)
				if rock_eff < 2.0:
					return "Life Orb"
		return "Leftovers"
	
	if counter.get("status", 0) == 0:
		if has_move(moves, "u-turn") or has_move(moves, "volt-switch") or role == "Fast Attacker":
			return "Expert Belt"
	
	if role in ["Fast Attacker", "Setup Sweeper", "Wallbreaker"]:
		var rock_eff = get_defensive_effectiveness("rock", types)
		if rock_eff < 2.0 and ability != "sturdy":
			return "Life Orb"
	
	return "Leftovers"

func build_move_counter(moves: Array, types: Array, preferred_type: String, abilities: Array) -> Dictionary:
	var counter = {
		"physical": 0, "special": 0, "status": 0, "damaging": 0,
		"stab": 0, "preferred": 0, "priority": 0, "setup": 0,
		"recovery": 0, "hazards": 0, "recoil": 0, "ironfist": 0, "sheerforce": 0,
	}
	
	for type_name in ["bug", "dark", "dragon", "electric", "fighting", "fire",
		"flying", "ghost", "grass", "ground", "ice", "normal", "poison",
		"psychic", "rock", "steel", "water"]:
		counter[type_name] = 0
	
	var recoil_moves = [
		"brave-bird", "double-edge", "flare-blitz", "head-smash",
		"high-jump-kick", "jump-kick", "submission", "take-down",
		"volt-tackle", "wild-charge", "wood-hammer",
	]
	
	var iron_fist_moves = [
		"bullet-punch", "comet-punch", "dizzy-punch", "drain-punch",
		"dynamic-punch", "fire-punch", "focus-punch", "hammer-arm",
		"ice-punch", "mach-punch", "mega-punch", "meteor-mash",
		"shadow-punch", "sky-uppercut", "thunder-punch",
	]
	
	var sheer_force_moves = [
		"air-slash", "ancient-power", "blaze-kick", "body-slam", "bounce",
		"bug-buzz", "charge-beam", "crunch", "dark-pulse", "discharge",
		"earth-power", "energy-ball", "extrasensory", "fake-out", "fire-blast",
		"fire-fang", "fire-punch", "fiery-dance", "flamethrower", "flash-cannon",
		"focus-blast", "force-palm", "headbutt", "heat-wave", "ice-beam",
		"ice-fang", "ice-punch", "icicle-crash", "iron-head", "iron-tail",
		"lava-plume", "low-sweep", "metal-claw", "meteor-mash", "mud-shot",
		"muddy-water", "night-daze", "poison-jab", "psychic", "rock-climb",
		"rock-slide", "rock-tomb", "scald", "seed-flare", "shadow-ball",
		"sludge-bomb", "snarl", "stomp", "struggle-bug", "thunder",
		"thunder-fang", "thunder-punch", "thunderbolt", "tri-attack",
		"waterfall", "zen-headbutt",
	]
	
	for move_name in moves:
		var mdata = get_move_details(move_name)
		var move_type = get_move_type(move_name, types, abilities, preferred_type)
		
		if mdata["category"] == "physical":
			counter["physical"] += 1
		elif mdata["category"] == "special":
			counter["special"] += 1
		else:
			counter["status"] += 1
		
		if mdata["category"] != "status" and mdata["power"] > 0:
			counter["damaging"] += 1
		
		if move_type in types and mdata["power"] > 0 and move_name not in NO_STAB:
			counter["stab"] += 1
		
		if preferred_type != "" and move_type == preferred_type and mdata["power"] > 0:
			counter["preferred"] += 1
		
		if mdata["power"] > 0 and counter.has(move_type):
			counter[move_type] += 1
		
		if mdata["priority"] > 0 and mdata["power"] > 0:
			counter["priority"] += 1
		if move_name in SETUP:
			counter["setup"] += 1
		if move_name in RECOVERY_MOVES:
			counter["recovery"] += 1
		if move_name in HAZARDS:
			counter["hazards"] += 1
		if move_name in recoil_moves:
			counter["recoil"] += 1
		if move_name in iron_fist_moves:
			counter["ironfist"] += 1
		if move_name in sheer_force_moves:
			counter["sheerforce"] += 1
	
	return counter

func run_enforcement_checker(type: String, move_pool: Array, moves: Array,
	abilities: Array, types: Array, counter: Dictionary, species_name: String) -> bool:
	
	var base_stats = gen5_pokemon.get(species_name, {})
	
	match type:
		"bug":
			return counter.get("bug", 0) == 0 and ("megahorn" in move_pool or "tinted-lens" in abilities)
		"dark":
			return counter.get("dark", 0) == 0
		"dragon":
			return counter.get("dragon", 0) == 0
		"electric":
			return counter.get("electric", 0) == 0
		"fighting":
			return counter.get("fighting", 0) == 0
		"fire":
			return counter.get("fire", 0) == 0
		"flying":
			return counter.get("flying", 0) == 0 and species_name not in ["aerodactyl", "mantine", "murkrow"] and "hidden-power-flying" not in move_pool
		"ghost":
			return counter.get("ghost", 0) == 0
		"grass":
			return counter.get("grass", 0) == 0 and (base_stats.get("attack", 0) >= 100 or "leaf-storm" in move_pool)
		"ground":
			return counter.get("ground", 0) == 0
		"ice":
			return counter.get("ice", 0) == 0
		"poison":
			return counter.get("poison", 0) == 0 and ("grass" in types or "ground" in types)
		"psychic":
			return counter.get("psychic", 0) == 0 and ("fighting" in types or "calm-mind" in move_pool)
		"rock":
			return counter.get("rock", 0) == 0 and base_stats.get("attack", 0) >= 80
		"steel":
			return counter.get("steel", 0) == 0 and species_name in ["aggron", "metagross"]
		"water":
			return counter.get("water", 0) == 0
	
	return false

func add_move(moveid: String, moves: Array, move_pool: Array):
	if moveid in moves or moves.size() >= 4:
		return
	moves.append(moveid)
	move_pool.erase(moveid)

func has_move(moves: Array, move_name: String) -> bool:
	return move_name in moves

func get_stab_moves(move_pool: Array, type: String, types: Array, abilities: Array, preferred_type: String) -> Array:
	var result = []
	for moveid in move_pool:
		var mdata = get_move_details(moveid)
		var move_type = get_move_type(moveid, types, abilities, preferred_type)
		if moveid not in NO_STAB and mdata["power"] > 0 and move_type == type:
			result.append(moveid)
	return result

func get_move_type(move_name: String, types: Array, abilities: Array, preferred_type: String) -> String:
	var mdata = get_move_details(move_name)
	var move_type = mdata["type"]
	if move_name == "judgment" and types.size() > 0:
		move_type = types[0]
	return move_type

func _default_max_pp(power: int, category: String) -> int:
	if category == "status": return 20
	if power >= 100:         return 5
	if power >= 70:          return 10
	if power >= 45:          return 15
	return 35

func get_move_details(move_name: String) -> Dictionary:
	if move_name.begins_with("hidden-power-"):
		var hp_type = move_name.replace("hidden-power-", "")
		return {"power": 60, "type": hp_type, "category": "special", "accuracy": 100, "priority": 0}
	if move_data.has(move_name):
		return move_data[move_name].duplicate()
	return {"power": 0, "type": "normal", "category": "status", "accuracy": 100, "priority": 0}

func get_defensive_effectiveness(atk_type: String, def_types: Array) -> float:
	var multiplier = 1.0
	for def_type in def_types:
		if type_chart.has(atk_type) and type_chart[atk_type].has(def_type):
			multiplier *= type_chart[atk_type][def_type]
	return multiplier

func optimize_hp_ev(base_hp: int, iv: int, ev: int, level: int,
	ability: String, moves: Array, item: String, types: Array) -> int:
	
	var sr_immunity = ability == "magic-guard"
	var sr_weakness = 0.0 if sr_immunity else get_defensive_effectiveness("rock", types)
	
	var hp_ev = ev
	while hp_ev > 1:
		var hp = int(floor((2.0 * base_hp + iv + floor(hp_ev / 4.0)) * level / 100.0) + level + 10)
		
		if has_move(moves, "substitute") and item not in ["Black Sludge", "Leftovers"]:
			if item == "Sitrus Berry":
				if hp % 4 == 0:
					break
			else:
				if hp % 4 > 0:
					break
		elif has_move(moves, "belly-drum") and item == "Sitrus Berry":
			if hp % 2 == 0:
				break
		elif has_move(moves, "high-jump-kick") or has_move(moves, "jump-kick"):
			if hp % 2 > 0:
				break
		else:
			if sr_weakness <= 0 or ability == "regenerator":
				break
			if sr_weakness == 1.0 and item in ["Black Sludge", "Leftovers", "Life Orb"]:
				break
			if item != "Sitrus Berry" and fmod(hp, 4.0 / sr_weakness) > 0:
				break
			if item == "Sitrus Berry" and fmod(hp, 4.0 / sr_weakness) == 0:
				break
		hp_ev -= 4
	
	return hp_ev
