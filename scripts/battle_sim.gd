extends Node

signal hp_changed(is_yours: bool, current_hp: int, max_hp: int)
signal pokemon_sent_out(is_yours: bool, current_hp: int, max_hp: int, mon_name: String)
signal battle_message(text: String)
signal pokemon_fainted(is_yours: bool, mon_name: String)
signal battle_ended(you_won: bool)

@export var team_gen_path: NodePath
var team_gen: Node

var your_team: Array = []
var opponent_team: Array = []
var your_active: int = 0
var opponent_active: int = 0
var battle_over: bool = false
var turn_count: int = 0

func _ready():
	team_gen = get_node(team_gen_path)
	start_battle()

func start_battle():
	var raw_your_team = team_gen.random_team()
	var raw_opponent_team = team_gen.random_team()
	
	your_team = []
	for raw_mon in raw_your_team:
		your_team.append(build_battle_pokemon(raw_mon))
	
	opponent_team = []
	for raw_mon in raw_opponent_team:
		opponent_team.append(build_battle_pokemon(raw_mon))
	
	your_active = 0
	opponent_active = 0
	battle_over = false
	turn_count = 0
	
	# Emit initial HP (instant, with names)
	var your_mon = your_team[your_active]
	var opp_mon = opponent_team[opponent_active]
	pokemon_sent_out.emit(true, your_mon["current_hp"], your_mon["max_hp"], your_mon["name"])
	pokemon_sent_out.emit(false, opp_mon["current_hp"], opp_mon["max_hp"], opp_mon["name"])
	
	print_teams()

func calc_hp(base: int, iv: int, ev: int, level: int) -> int:
	return int(floor((2.0 * base + iv + floor(ev / 4.0)) * level / 100.0) + level + 10)

func calc_stat(base: int, iv: int, ev: int, level: int) -> int:
	return int(floor((floor((2.0 * base + iv + floor(ev / 4.0)) * level / 100.0) + 5) * 1.0))

func build_battle_pokemon(raw: Dictionary) -> Dictionary:
	var ivs = raw["ivs"]
	var evs = raw["evs"]
	var level = raw["level"]
	
	var hp = calc_hp(raw["base_hp"], ivs["hp"], evs["hp"], level)
	if raw["name"] == "shedinja":
		hp = 1
	
	return {
		"name": raw["name"],
		"level": level,
		"types": raw["types"],
		"ability": raw["ability"],
		"item": raw["item"],
		"role": raw["role"],
		"moveset": raw["moveset"],
		"move_names": raw["move_names"],
		"max_hp": hp,
		"current_hp": hp,
		"attack": calc_stat(raw["base_attack"], ivs["atk"], evs["atk"], level),
		"defense": calc_stat(raw["base_defense"], ivs["def"], evs["def"], level),
		"sp_atk": calc_stat(raw["base_sp_atk"], ivs["spa"], evs["spa"], level),
		"sp_def": calc_stat(raw["base_sp_def"], ivs["spd"], evs["spd"], level),
		"speed": calc_stat(raw["base_speed"], ivs["spe"], evs["spe"], level),
		"atk_stage": 0,
		"def_stage": 0,
		"spa_stage": 0,
		"spd_stage": 0,
		"spe_stage": 0,
		"accuracy_stage": 0,
		"evasion_stage": 0,
		"status": "",
		"toxic_counter": 0,
		"is_fainted": false,
	}

func get_stat_multiplier(stage: int) -> float:
	if stage >= 0:
		return (2.0 + stage) / 2.0
	else:
		return 2.0 / (2.0 - stage)

func get_effective_stat(mon: Dictionary, stat_name: String) -> int:
	var base_val = mon[stat_name]
	var stage_key = ""
	match stat_name:
		"attack":
			stage_key = "atk_stage"
		"defense":
			stage_key = "def_stage"
		"sp_atk":
			stage_key = "spa_stage"
		"sp_def":
			stage_key = "spd_stage"
		"speed":
			stage_key = "spe_stage"
	
	if stage_key == "":
		return base_val
	
	var multiplier = get_stat_multiplier(mon[stage_key])
	return int(base_val * multiplier)

func calculate_damage(attacker: Dictionary, defender: Dictionary, move: Dictionary) -> int:
	if move["category"] == "status" or move["power"] == 0:
		return 0
	
	var level = attacker["level"]
	var power = move["power"]
	
	var atk: float
	var def_stat: float
	if move["category"] == "physical":
		atk = get_effective_stat(attacker, "attack")
		def_stat = get_effective_stat(defender, "defense")
		if attacker["status"] == "burn":
			atk *= 0.5
	else:
		atk = get_effective_stat(attacker, "sp_atk")
		def_stat = get_effective_stat(defender, "sp_def")
	
	var base_damage = ((2.0 * level / 5.0 + 2.0) * power * atk / def_stat) / 50.0 + 2.0
	
	var stab = 1.0
	if move["type"] in attacker["types"]:
		stab = 1.5
		if attacker["ability"] == "adaptability":
			stab = 2.0
	
	var effectiveness = get_type_effectiveness(move["type"], defender["types"])
	var random_roll = randf_range(0.85, 1.0)
	
	var item_mod = 1.0
	match attacker["item"]:
		"Life Orb":
			item_mod = 1.3
		"Expert Belt":
			if effectiveness > 1.0:
				item_mod = 1.2
		"Choice Band":
			if move["category"] == "physical":
				item_mod = 1.5
		"Choice Specs":
			if move["category"] == "special":
				item_mod = 1.5
	
	var final_damage = int(base_damage * stab * effectiveness * random_roll * item_mod)
	return max(final_damage, 1)

func get_type_effectiveness(move_type: String, defender_types: Array) -> float:
	var type_chart = team_gen.type_chart
	var multiplier = 1.0
	for def_type in defender_types:
		if type_chart.has(move_type) and type_chart[move_type].has(def_type):
			multiplier *= type_chart[move_type][def_type]
	return multiplier

func accuracy_check(attacker: Dictionary, defender: Dictionary, move: Dictionary) -> bool:
	if move["accuracy"] == 0:
		return true
	
	var accuracy = move["accuracy"]
	var stage_diff = attacker["accuracy_stage"] - defender["evasion_stage"]
	var stage_mod = get_stat_multiplier(clampi(stage_diff, -6, 6))
	
	var final_accuracy = int(accuracy * stage_mod)
	return randi() % 100 < final_accuracy

func execute_turn(your_move_index: int, opponent_move_index: int):
	if battle_over:
		return
	
	turn_count += 1
	var your_mon = your_team[your_active]
	var opp_mon = opponent_team[opponent_active]
	
	var your_move = your_mon["moveset"][your_move_index]
	var opp_move = opp_mon["moveset"][opponent_move_index]
	
	var your_priority = your_move["priority"]
	var opp_priority = opp_move["priority"]
	
	var your_speed = get_effective_stat(your_mon, "speed")
	var opp_speed = get_effective_stat(opp_mon, "speed")
	
	if your_mon["status"] == "paralyze":
		your_speed = int(your_speed * 0.25)
	if opp_mon["status"] == "paralyze":
		opp_speed = int(opp_speed * 0.25)
	
	if your_mon["item"] == "Choice Scarf":
		your_speed = int(your_speed * 1.5)
	if opp_mon["item"] == "Choice Scarf":
		opp_speed = int(opp_speed * 1.5)
	
	var you_go_first: bool
	if your_priority != opp_priority:
		you_go_first = your_priority > opp_priority
	elif your_speed != opp_speed:
		you_go_first = your_speed > opp_speed
	else:
		you_go_first = randi() % 2 == 0
	
	if you_go_first:
		execute_move(your_mon, opp_mon, your_move, true)
		if not opp_mon["is_fainted"]:
			execute_move(opp_mon, your_mon, opp_move, false)
	else:
		execute_move(opp_mon, your_mon, opp_move, false)
		if not your_mon["is_fainted"]:
			execute_move(your_mon, opp_mon, your_move, true)
	
	apply_end_of_turn(your_mon, true)
	apply_end_of_turn(opp_mon, false)
	
	check_faint(true)
	check_faint(false)

func execute_move(attacker: Dictionary, defender: Dictionary, move: Dictionary, is_yours: bool):
	if attacker["is_fainted"]:
		return
	
	var side = "Your" if is_yours else "Opponent's"
	
	if attacker["status"] == "paralyze" and randi() % 4 == 0:
		battle_message.emit(attacker["name"] + " is fully paralyzed!")
		return
	
	if attacker["status"] == "sleep":
		if randi() % 3 == 0:
			attacker["status"] = ""
			battle_message.emit(attacker["name"] + " woke up!")
		else:
			battle_message.emit(attacker["name"] + " is fast asleep!")
			return
	
	if attacker["status"] == "freeze":
		if randi() % 5 == 0:
			attacker["status"] = ""
			battle_message.emit(attacker["name"] + " thawed out!")
		else:
			battle_message.emit(attacker["name"] + " is frozen solid!")
			return
	
	battle_message.emit(attacker["name"] + " used " + move["name"] + "!")
	
	if not accuracy_check(attacker, defender, move):
		battle_message.emit("It missed!")
		return
	
	if move["category"] != "status" and move["power"] > 0:
		var damage = calculate_damage(attacker, defender, move)
		var effectiveness = get_type_effectiveness(move["type"], defender["types"])
		
		defender["current_hp"] = max(defender["current_hp"] - damage, 0)
		hp_changed.emit(not is_yours, defender["current_hp"], defender["max_hp"])
		
		battle_message.emit("Dealt " + str(damage) + " damage!")
		
		if effectiveness > 1.0:
			battle_message.emit("It's super effective!")
		elif effectiveness < 1.0 and effectiveness > 0.0:
			battle_message.emit("It's not very effective...")
		elif effectiveness == 0.0:
			battle_message.emit("It had no effect!")
		
		# Life Orb recoil
		if attacker["item"] == "Life Orb" and attacker["ability"] != "magic-guard":
			var recoil = max(int(attacker["max_hp"] / 10), 1)
			attacker["current_hp"] = max(attacker["current_hp"] - recoil, 0)
			hp_changed.emit(is_yours, attacker["current_hp"], attacker["max_hp"])
			battle_message.emit(attacker["name"] + " lost HP to Life Orb!")
		
		if defender["current_hp"] <= 0:
			defender["is_fainted"] = true
			pokemon_fainted.emit(not is_yours, defender["name"])

func apply_end_of_turn(mon: Dictionary, is_yours: bool):
	if mon["is_fainted"]:
		return
	
	if mon["status"] == "burn":
		var burn_dmg = max(int(mon["max_hp"] / 8), 1)
		mon["current_hp"] = max(mon["current_hp"] - burn_dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["name"] + " was hurt by its burn!")
	
	if mon["status"] == "poison":
		var poison_dmg = max(int(mon["max_hp"] / 8), 1)
		mon["current_hp"] = max(mon["current_hp"] - poison_dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["name"] + " was hurt by poison!")
	
	if mon["status"] == "toxic":
		mon["toxic_counter"] += 1
		var toxic_dmg = max(int(mon["max_hp"] * mon["toxic_counter"] / 16), 1)
		mon["current_hp"] = max(mon["current_hp"] - toxic_dmg, 0)
		hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
		battle_message.emit(mon["name"] + " was hurt by toxic!")
	
	if mon["item"] == "Leftovers" or mon["item"] == "Black Sludge":
		if mon["current_hp"] < mon["max_hp"]:
			var heal = max(int(mon["max_hp"] / 16), 1)
			mon["current_hp"] = min(mon["current_hp"] + heal, mon["max_hp"])
			hp_changed.emit(is_yours, mon["current_hp"], mon["max_hp"])
			battle_message.emit(mon["name"] + " restored HP with " + mon["item"] + "!")
	
	if mon["current_hp"] <= 0:
		mon["is_fainted"] = true
		pokemon_fainted.emit(is_yours, mon["name"])

func check_faint(is_yours: bool):
	var team = your_team if is_yours else opponent_team
	var active = your_active if is_yours else opponent_active
	
	if not team[active]["is_fainted"]:
		return
	
	var next = find_next_alive(team)
	if next == -1:
		battle_over = true
		battle_ended.emit(not is_yours)
		return
	
	if is_yours:
		your_active = next
	else:
		opponent_active = next
	
	var mon = team[next]
	pokemon_sent_out.emit(is_yours, mon["current_hp"], mon["max_hp"], mon["name"])
	battle_message.emit(mon["name"] + " was sent out!")

func find_next_alive(team: Array) -> int:
	for i in team.size():
		if not team[i]["is_fainted"]:
			return i
	return -1

func switch_pokemon(is_yours: bool, index: int):
	var team = your_team if is_yours else opponent_team
	if index < 0 or index >= team.size():
		return
	if team[index]["is_fainted"]:
		return
	
	if is_yours:
		your_active = index
	else:
		opponent_active = index
	
	var mon = team[index]
	mon["atk_stage"] = 0
	mon["def_stage"] = 0
	mon["spa_stage"] = 0
	mon["spd_stage"] = 0
	mon["spe_stage"] = 0
	mon["accuracy_stage"] = 0
	mon["evasion_stage"] = 0
	mon["toxic_counter"] = 0

	pokemon_sent_out.emit(is_yours, mon["current_hp"], mon["max_hp"], mon["name"])
	battle_message.emit(mon["name"] + " was sent out!")

func get_opponent_move() -> int:
	return randi() % opponent_team[opponent_active]["moveset"].size()

func print_teams():
	print("=== YOUR TEAM ===")
	for mon in your_team:
		print(mon["name"], " Lv", mon["level"], " | HP: ", mon["max_hp"],
			" | Atk: ", mon["attack"], " | Def: ", mon["defense"],
			" | SpA: ", mon["sp_atk"], " | SpD: ", mon["sp_def"],
			" | Spe: ", mon["speed"])
		print("  ", mon["ability"], " | ", mon["item"])
		var move_names = []
		for m in mon["moveset"]:
			move_names.append(m["name"])
		print("  Moves: ", move_names)
	
	print("\n=== OPPONENT TEAM ===")
	for mon in opponent_team:
		print(mon["name"], " Lv", mon["level"], " | HP: ", mon["max_hp"],
			" | Atk: ", mon["attack"], " | Def: ", mon["defense"],
			" | SpA: ", mon["sp_atk"], " | SpD: ", mon["sp_def"],
			" | Spe: ", mon["speed"])
		print("  ", mon["ability"], " | ", mon["item"])
		var move_names = []
		for m in mon["moveset"]:
			move_names.append(m["name"])
		print("  Moves: ", move_names)
