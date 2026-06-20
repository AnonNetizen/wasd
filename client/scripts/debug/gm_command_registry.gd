# Doc: docs/代码/debug_tools.md
# Authority: docs/游戏设计文档.md §9.20, docs/词表与契约.md §9
class_name GMCommandRegistry
extends Node


const COMMAND_HELP: String = "help"
const COMMAND_STATS: String = "stats"
const COMMAND_SPAWN: String = "spawn"
const COMMAND_XP: String = "xp"
const COMMAND_HEAL: String = "heal"
const COMMAND_HP: String = "hp"
const COMMAND_DAMAGE: String = "damage"
const COMMAND_KILL_PLAYER: String = "kill_player"
const COMMAND_KILL_ENEMIES: String = "kill_enemies"
const COMMAND_CLEAR_ENEMIES: String = "clear_enemies"
const COMMAND_META: String = "meta"
const COMMAND_SEED: String = "seed"

const DEFAULT_SPAWN_ENEMY_ID: String = "enemy_chaser"
const MAX_SPAWN_COUNT: int = 50

var _boot: Node = null


func setup(boot: Node) -> void:
	_boot = boot


func execute(raw_command: String) -> Dictionary:
	var tokens: PackedStringArray = _tokens(raw_command)
	if tokens.is_empty():
		return _result(false, "empty command")

	var command: String = String(tokens[0]).to_lower()
	match command:
		COMMAND_HELP:
			return _result(true, _help_text())
		COMMAND_STATS:
			return _stats()
		COMMAND_SPAWN:
			return _spawn(tokens)
		COMMAND_XP:
			return _xp(tokens)
		COMMAND_HEAL:
			return _heal(tokens)
		COMMAND_HP:
			return _hp(tokens)
		COMMAND_DAMAGE:
			return _damage(tokens)
		COMMAND_KILL_PLAYER:
			return _kill_player()
		COMMAND_KILL_ENEMIES:
			return _kill_enemies()
		COMMAND_CLEAR_ENEMIES:
			return _clear_enemies()
		COMMAND_META:
			return _meta(tokens)
		COMMAND_SEED:
			return _seed(tokens)
		_:
			return _result(false, "unknown command: %s" % command)


func available_commands() -> PackedStringArray:
	return PackedStringArray([
		COMMAND_HELP,
		COMMAND_STATS,
		COMMAND_SPAWN,
		COMMAND_XP,
		COMMAND_HEAL,
		COMMAND_HP,
		COMMAND_DAMAGE,
		COMMAND_KILL_PLAYER,
		COMMAND_KILL_ENEMIES,
		COMMAND_CLEAR_ENEMIES,
		COMMAND_META,
		COMMAND_SEED,
	])


func _stats() -> Dictionary:
	var run_loop: Node = _active_run_loop()
	var run_text: String = "run=none"
	if run_loop != null and run_loop.has_method("debug_summary"):
		var summary: Dictionary = run_loop.call("debug_summary")
		run_text = "run=level:%d xp:%d life:%.1f/%.1f kills:%d enemies:%d" % [
			int(summary.get("level", 0)),
			int(summary.get("xp", 0)),
			float(summary.get("player_life", 0.0)),
			float(summary.get("player_max_life", 0.0)),
			int(summary.get("kills", 0)),
			int(summary.get("active_enemies", 0)),
		]
	return _result(true, "state=%s seed=%d time=%.2f ui=%d pools=%d active_enemies=%d %s" % [
		String(GameState.current()),
		RNG.run_seed(),
		GameClock.now(),
		UIManager.stack_size(),
		PoolManager.pool_count(),
		get_tree().get_nodes_in_group("active_enemies").size(),
		run_text,
	])


func _spawn(tokens: PackedStringArray) -> Dictionary:
	var run_loop: Node = _required_run_loop("spawn")
	if run_loop == null:
		return _result(false, "spawn requires an active run")
	var enemy_id: String = String(tokens[1]) if tokens.size() > 1 else DEFAULT_SPAWN_ENEMY_ID
	var count: int = clampi(_int_arg(tokens, 2, 1), 1, MAX_SPAWN_COUNT)
	var result: Dictionary = run_loop.call("debug_spawn_enemy", enemy_id, count)
	if not bool(result.get("ok", false)):
		return _result(false, String(result.get("reason", "spawn failed")))
	return _result(true, "spawned %d %s" % [int(result.get("spawned", 0)), enemy_id])


func _xp(tokens: PackedStringArray) -> Dictionary:
	var run_loop: Node = _required_run_loop("xp")
	if run_loop == null:
		return _result(false, "xp requires an active run")
	var amount: int = maxi(_int_arg(tokens, 1, 1), 1)
	var result: Dictionary = run_loop.call("debug_give_xp", amount)
	if not bool(result.get("ok", false)):
		return _result(false, String(result.get("reason", "xp failed")))
	return _result(true, "xp +%d total=%d level=%d" % [
		amount,
		int(result.get("xp", 0)),
		int(result.get("level", 0)),
	])


func _heal(tokens: PackedStringArray) -> Dictionary:
	var run_loop: Node = _required_run_loop("heal")
	if run_loop == null:
		return _result(false, "heal requires an active run")
	var amount: float = maxf(_float_arg(tokens, 1, 9999.0), 0.0)
	var result: Dictionary = run_loop.call("debug_heal_player", amount)
	return _life_result("healed", result)


func _hp(tokens: PackedStringArray) -> Dictionary:
	var run_loop: Node = _required_run_loop("hp")
	if run_loop == null:
		return _result(false, "hp requires an active run")
	var amount: float = _float_arg(tokens, 1, 1.0)
	var result: Dictionary = run_loop.call("debug_set_player_hp", amount)
	return _life_result("hp", result)


func _damage(tokens: PackedStringArray) -> Dictionary:
	var run_loop: Node = _required_run_loop("damage")
	if run_loop == null:
		return _result(false, "damage requires an active run")
	var amount: float = maxf(_float_arg(tokens, 1, 1.0), 0.0)
	var result: Dictionary = run_loop.call("debug_damage_player", amount)
	if not bool(result.get("ok", false)):
		return _result(false, String(result.get("reason", "damage failed")))
	return _result(true, "damage %.1f life=%.1f/%.1f" % [
		amount,
		float(result.get("life", 0.0)),
		float(result.get("max_life", 0.0)),
	])


func _kill_player() -> Dictionary:
	var run_loop: Node = _required_run_loop("kill_player")
	if run_loop == null:
		return _result(false, "kill_player requires an active run")
	var result: Dictionary = run_loop.call("debug_kill_player")
	if not bool(result.get("ok", false)):
		return _result(false, String(result.get("reason", "kill failed")))
	return _result(true, "player killed")


func _kill_enemies() -> Dictionary:
	var run_loop: Node = _required_run_loop("kill_enemies")
	if run_loop == null:
		return _result(false, "kill_enemies requires an active run")
	var result: Dictionary = run_loop.call("debug_kill_enemies")
	return _result(bool(result.get("ok", false)), "killed enemies=%d" % int(result.get("count", 0)))


func _clear_enemies() -> Dictionary:
	var run_loop: Node = _required_run_loop("clear_enemies")
	if run_loop == null:
		return _result(false, "clear_enemies requires an active run")
	var result: Dictionary = run_loop.call("debug_clear_enemies")
	return _result(bool(result.get("ok", false)), "cleared enemies=%d" % int(result.get("count", 0)))


func _meta(tokens: PackedStringArray) -> Dictionary:
	var amount: int = maxi(_int_arg(tokens, 1, 1), 1)
	var result: Dictionary = MetaProgressionSystem.debug_grant_currency(amount)
	if not bool(result.get("ok", false)):
		return _result(false, String(result.get("reason", "meta failed")))
	return _result(true, "meta +%d %s=%d" % [
		amount,
		String(result.get("currency_id", "")),
		int(result.get("balance", 0)),
	])


func _seed(tokens: PackedStringArray) -> Dictionary:
	var seed_value: int = maxi(_int_arg(tokens, 1, 1), 1)
	RNG.set_run_seed(seed_value)
	return _result(true, "seed=%d" % RNG.run_seed())


func _life_result(prefix: String, result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		return _result(false, String(result.get("reason", "%s failed" % prefix)))
	return _result(true, "%s life=%.1f/%.1f" % [
		prefix,
		float(result.get("life", 0.0)),
		float(result.get("max_life", 0.0)),
	])


func _required_run_loop(_command: String) -> Node:
	var run_loop: Node = _active_run_loop()
	if run_loop == null:
		return null
	return run_loop if run_loop.has_method("debug_summary") else null


func _active_run_loop() -> Node:
	if _boot != null and is_instance_valid(_boot) and _boot.has_method("debug_active_run_loop"):
		var from_boot: Node = _boot.call("debug_active_run_loop")
		if from_boot != null and is_instance_valid(from_boot):
			return from_boot
	return _find_node_by_name(get_tree().root, "GameplayRunLoop")


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child: Node in root.get_children():
		var found: Node = _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _help_text() -> String:
	return "commands: help, stats, spawn <enemy_id> [count], xp <amount>, heal [amount], hp <amount>, damage <amount>, kill_player, kill_enemies, clear_enemies, meta <amount>, seed <int>"


func _tokens(raw_command: String) -> PackedStringArray:
	return raw_command.strip_edges().split(" ", false)


func _int_arg(tokens: PackedStringArray, index: int, fallback: int) -> int:
	if index >= tokens.size():
		return fallback
	if not String(tokens[index]).is_valid_int():
		return fallback
	return String(tokens[index]).to_int()


func _float_arg(tokens: PackedStringArray, index: int, fallback: float) -> float:
	if index >= tokens.size():
		return fallback
	if not String(tokens[index]).is_valid_float():
		return fallback
	return String(tokens[index]).to_float()


func _result(ok: bool, message: String) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
	}
