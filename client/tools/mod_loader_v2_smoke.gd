extends SceneTree


const MOD_LOADER_SCRIPT := preload("res://scripts/autoload/mod_loader.gd")
const GEAR_MOD_DROP_TABLES_PATH: String = (
	"res://data/gear_mod_drop_tables.csv"
)
const TEST_ROOTS: Array[String] = [
	"user://mods/l1_mod_v2_alpha",
	"user://mods/l1_mod_v2_bad",
	"user://mods/l1_mod_v2_deep_bad",
	"user://mods/l1_mod_v2_manifest_bad",
	"user://mods/l1_mod_v2_zeta",
	"user://mods/l1_mod_v2_manifest_budget",
	"user://mods/l1_mod_v2_patch_budget",
	"user://mods/l1_mod_v2_total_budget",
	"user://mods/l1_mod_v2_json_depth_budget",
	"user://mods/l1_mod_v2_json_node_budget",
	"user://mods/l1_mod_v2_csv_row_budget",
	"user://mods/l1_mod_v2_csv_column_budget",
]

var _failures: Array[String] = []
var _mod_loader: Node = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_mod_loader = MOD_LOADER_SCRIPT.new()
	get_root().add_child(_mod_loader)
	_cleanup()
	_write_valid_package("l1_mod_v2_zeta", -5)
	_write_valid_package("l1_mod_v2_alpha", -5)
	_write_invalid_package()
	_write_deep_invalid_package()
	_write_invalid_manifest_package()
	_write_resource_budget_packages()
	_expect(_reload_packages(), "main-menu package reload should succeed")
	_expect(int(_mod_loader.call("enabled_mod_count")) == 3, "package validation should keep the DataLoader-level fixture until full schema validation")
	_expect(_diagnostics_contain("manifest v2 fields only"), "manifest v2 should reject undeclared top-level fields")
	_expect(_diagnostics_contain("JSON file budget of %d bytes" % MOD_LOADER_SCRIPT.MAX_MANIFEST_BYTES), "oversized manifest should be isolated")
	_expect(_diagnostics_contain("file at most %d bytes" % MOD_LOADER_SCRIPT.MAX_GAMEPLAY_PATCH_FILE_BYTES), "oversized gameplay patch should be isolated")
	_expect(_diagnostics_contain("patch declarations totaling at most %d bytes" % MOD_LOADER_SCRIPT.MAX_GAMEPLAY_PATCH_TOTAL_BYTES), "repeated gameplay patch declarations should count toward the package budget")
	_expect(_diagnostics_contain("JSON depth budget of %d" % MOD_LOADER_SCRIPT.MAX_GAMEPLAY_JSON_DEPTH), "overly deep gameplay JSON should be isolated")
	_expect(_diagnostics_contain("JSON node budget of %d" % MOD_LOADER_SCRIPT.MAX_GAMEPLAY_JSON_NODES), "oversized gameplay JSON tree should be isolated")
	_expect(_diagnostics_contain("CSV row budget of %d" % MOD_LOADER_SCRIPT.MAX_GAMEPLAY_CSV_ROWS), "oversized gameplay CSV row set should be isolated")
	_expect(_diagnostics_contain("CSV column budget of %d" % MOD_LOADER_SCRIPT.MAX_GAMEPLAY_CSV_COLUMNS), "oversized gameplay CSV column set should be isolated")

	var environment: Array[Dictionary] = _mod_loader.call("mod_environment") as Array[Dictionary]
	_expect(environment.size() == 3, "environment should contain package-level valid gameplay packages")
	if environment.size() == 3:
		_expect(String(environment[0].get("id", "")) == "l1_mod_v2_alpha", "same-order packages should sort by id")
		_expect(String(environment[0].get("gameplay_hash", "")).length() == 64, "gameplay hash should be sha256")
	var gameplay_payloads: Array[Dictionary] = _mod_loader.call("package_gameplay_payloads") as Array[Dictionary]
	_expect(gameplay_payloads.size() == 3, "package gameplay payload API should expose package-level valid packages")
	if gameplay_payloads.size() == 3:
		_expect((gameplay_payloads[0].get("mods", []) as Array).size() == 1, "package gameplay payload should contain cached Gear Mods")
		_expect((gameplay_payloads[0].get("reward_pool_contributions", []) as Array).size() == 1, "package gameplay payload should contain reward pool contributions")
		_expect((gameplay_payloads[0].get("drop_rows", []) as Array).size() == 1, "package gameplay payload should contain enemy drop rows")
		_expect(
			String(gameplay_payloads[2].get("id", ""))
			== "l1_mod_v2_deep_bad"
			and (gameplay_payloads[2].get("drop_rows", []) as Array).size()
			== 1,
			"DataLoader-level invalid package should begin with a legal drop row"
		)
		var alpha_definition: Dictionary = (gameplay_payloads[0].get("mods") as Array)[0] as Dictionary
		var zeta_definition: Dictionary = (gameplay_payloads[1].get("mods") as Array)[0] as Dictionary
		_expect(String(alpha_definition.get("codex_icon_path", "")) == "mod_l1_mod_v2_alpha_icon", "valid package icon media id should remain registered")
		_expect(not zeta_definition.has("codex_icon_path"), "missing package image should fall back without disabling gameplay")
		_expect(String(alpha_definition.get("placement_sfx_id", "")) == "mod_l1_mod_v2_alpha_valid_sfx", "valid package placement SFX id should remain registered")
		_expect(not zeta_definition.has("placement_sfx_id"), "invalid package placement SFX should fall back to silence")
		((gameplay_payloads[0].get("mods") as Array)[0] as Dictionary)["id"] = "mutated"
		var fresh_payloads: Array[Dictionary] = _mod_loader.call("package_gameplay_payloads") as Array[Dictionary]
		_expect(String(((fresh_payloads[0].get("mods") as Array)[0] as Dictionary).get("id", "")) != "mutated", "package gameplay payload should be a deep copy")
	_expect(bool((_mod_loader.call("validate_environment", environment) as Dictionary).get("ok", false)), "exact environment should validate")
	var mismatch: Array = environment.duplicate(true)
	if not mismatch.is_empty():
		(mismatch[0] as Dictionary)["version"] = "wrong"
	_expect(not bool((_mod_loader.call("validate_environment", mismatch) as Dictionary).get("ok", true)), "version mismatch should be rejected")

	_expect(bool(_mod_loader.call("has_image_asset", "mod_l1_mod_v2_alpha_icon")), "valid package PNG should register")
	_expect(_mod_loader.call("image_texture", "mod_l1_mod_v2_alpha_icon") != null, "registered image should return ImageTexture")
	_expect(_has_audio("mod_l1_mod_v2_alpha_valid_sfx"), "valid package WAV should register")
	var audio_manager: Node = get_root().get_node_or_null("AudioManager")
	var valid_audio: Dictionary = _audio_entry("mod_l1_mod_v2_alpha_valid_sfx")
	if audio_manager != null and not valid_audio.is_empty():
		_expect(
			bool(audio_manager.call(
				"register_mod_sfx",
				"l1_mod_v2_alpha",
				"mod_l1_mod_v2_alpha_valid_sfx",
				valid_audio.get("stream"),
				4
			)),
			"AudioManager should accept package-namespaced non-looping SFX"
		)
		_expect(bool(audio_manager.call("has_stream", "mod_l1_mod_v2_alpha_valid_sfx")), "AudioManager should route registered package SFX")
		_expect(bool(audio_manager.call("play_sfx", "mod_l1_mod_v2_alpha_valid_sfx")), "registered package SFX should be playable through AudioManager")
		audio_manager.call("stop_all_sfx")
	_expect(not _has_audio("mod_l1_mod_v2_alpha_broken_sfx"), "invalid audio should fall back to silence")
	_expect(_diagnostics_contain("media fallback"), "invalid media should retain a diagnostic")
	var global_mod_loader: Node = get_root().get_node_or_null("ModLoader")
	var data_loader: Node = get_root().get_node_or_null("DataLoader")
	var localization: Node = get_root().get_node_or_null("Localization")
	if global_mod_loader != null and data_loader != null and localization != null:
		global_mod_loader.call("reload_packages")
		data_loader.call("reload_contracts")
		_expect(bool(data_loader.call("validate_project_data")), "full DataLoader schema should isolate a bad package without failing base data")
		_expect(int(global_mod_loader.call("enabled_mod_count")) == 2, "DataLoader should disable only the package with an invalid hero-slot stat")
		var schema_counts: Dictionary = (
			data_loader.call("schema_counts") as Dictionary
		)
		_expect(
			int(schema_counts.get("gear_mod_drop_rows", -1)) == 7,
			"merged drop count should exclude the isolated package"
		)
		var merged_drop_rows: Array[Dictionary] = data_loader.call(
			"load_csv",
			GEAR_MOD_DROP_TABLES_PATH
		) as Array[Dictionary]
		var merged_drop_mod_ids: Array[String] = []
		for row: Dictionary in merged_drop_rows:
			merged_drop_mod_ids.append(String(row.get("mod_id", "")))
		_expect(
			not merged_drop_mod_ids.has(
				"mod_l1_mod_v2_deep_bad_gear"
			),
			"isolated package drop rows should not remain merged"
		)
		if merged_drop_rows.size() == 7:
			_expect(
				merged_drop_mod_ids[5]
				== "mod_l1_mod_v2_alpha_test_gear"
				and merged_drop_mod_ids[6]
				== "mod_l1_mod_v2_zeta_test_gear",
				"valid package drop rows should keep package order"
			)
		var deep_bad_status_found: bool = false
		for status: Dictionary in global_mod_loader.call("package_statuses") as Array[Dictionary]:
			if String(status.get("id", "")) != "l1_mod_v2_deep_bad":
				continue
			deep_bad_status_found = (
				String(status.get("status", "")) == "invalid"
				and not bool(status.get("enabled", true))
			)
		_expect(deep_bad_status_found, "DataLoader-isolated package should remain visible with invalid status")
		localization.call("set_locale", "zh_CN")
		_expect(TranslationServer.translate(&"mod_l1_mod_v2_alpha_name") == "\u6d4b\u8bd5\u6a21\u7ec4", "zh_CN local package translation should be registered")
		localization.call("set_locale", "en")
		_expect(TranslationServer.translate(&"mod_l1_mod_v2_alpha_name") == "Test Mod", "English local package translation should be registered")

	var before: Dictionary = _mod_loader.call("apply_json_mods", "res://data/gear_mods.json", {"mods": [], "reward_pool_contributions": []}) as Dictionary
	_write_text(TEST_ROOTS[0].path_join("data/gear_mods.json"), "{}")
	var after: Dictionary = _mod_loader.call("apply_json_mods", "res://data/gear_mods.json", {"mods": [], "reward_pool_contributions": []}) as Dictionary
	_expect(before == after, "package data should remain an immutable snapshot until explicit reload")
	_expect((before.get("reward_pool_contributions", []) as Array).size() == 2, "two packages should append reward pool contributions")
	var empty_locale_rows: Array[Dictionary] = []
	var localized_rows: Array[Dictionary] = _mod_loader.call("apply_csv_mods", "res://locale/strings.csv", empty_locale_rows) as Array[Dictionary]
	_expect(localized_rows.size() == 6, "three package-level valid packages should append bilingual locale rows before DataLoader isolation")

	_mod_loader.call("set_runtime_activity", true, false)
	_expect(not _reload_packages(), "active Run should reject package reload")
	_mod_loader.call("set_runtime_activity", false, true)
	_expect(not _reload_packages(), "active Replay should reject package reload")
	_mod_loader.call("set_runtime_activity", false, false)

	_cleanup()
	if global_mod_loader != null:
		global_mod_loader.call("reload_packages")
	_reload_packages()
	_finish()


func _write_valid_package(package_id: String, load_order: int) -> void:
	var root: String = "user://mods/%s" % package_id
	var make_error: Error = DirAccess.make_dir_recursive_absolute(root.path_join("media"))
	_expect(make_error == OK, "%s directories should be created" % package_id)
	DirAccess.make_dir_recursive_absolute(root.path_join("data"))
	var gear_mod_id: String = "mod_%s_test_gear" % package_id
	var icon_asset_id: String = "mod_%s_icon" % package_id if package_id == "l1_mod_v2_alpha" else "mod_%s_missing_icon" % package_id
	var placement_sfx_id: String = "mod_%s_valid_sfx" % package_id if package_id == "l1_mod_v2_alpha" else "mod_%s_broken_sfx" % package_id
	var manifest: Dictionary = {
		"schema_version": 2,
		"id": package_id,
		"name": package_id,
		"version": "1.0.0",
		"enabled": true,
		"load_order": load_order,
		"contract_extensions": {
			"gear_mod_ids": [gear_mod_id],
			"locale_prefixes": ["mod_%s_" % package_id],
		},
		"data_patches": [
			{
				"type": "json_array_append",
				"target": "gear_mods.json",
				"path": "data/gear_mods.json",
				"array_key": "mods",
			},
			{
				"type": "csv_append",
				"target": "gear_mod_drop_tables.csv",
				"path": "data/drops.csv",
			},
			{
				"type": "json_array_append",
				"target": "gear_mods.json",
				"path": "data/gear_mods.json",
				"array_key": "reward_pool_contributions",
			},
			{
				"type": "csv_append",
				"target": "strings.csv",
				"path": "data/strings.csv",
			},
		],
		"media_assets": [
			{
				"id": "mod_%s_icon" % package_id,
				"type": "image",
				"path": "media/icon.png",
			},
			{
				"id": "mod_%s_valid_sfx" % package_id,
				"type": "sfx",
				"path": "media/valid.wav",
			},
			{
				"id": "mod_%s_broken_sfx" % package_id,
				"type": "sfx",
				"path": "media/broken.ogg",
			},
			{
				"id": "mod_%s_escape_image" % package_id,
				"type": "image",
				"path": "../escape.png",
			},
		],
	}
	_write_text(root.path_join("mod.json"), JSON.stringify(manifest, "\t"))
	_write_text(
		root.path_join("data/gear_mods.json"),
		JSON.stringify(
			{
				"mods": [
					{
						"id": gear_mod_id,
						"name_key": "mod_%s_name" % package_id,
						"desc_key": "mod_%s_desc" % package_id,
						"default_unlocked": true,
						"rarity": "common",
						"codex_icon_path": icon_asset_id,
						"placement_sfx_id": placement_sfx_id,
						"components": [
							{
								"component_id": "occupy_cell",
								"type": "board_rule",
								"rule_id": "occupy_only",
							},
						],
					},
				],
				"reward_pool_contributions": [
					{
						"pool_id": "world_event_mod_pool_common",
						"mod_ids": [gear_mod_id],
					},
				],
			},
			"\t"
		)
	)
	_write_text(
		root.path_join("data/drops.csv"),
		"source_enemy_id,mod_id,drop_chance,min_enemy_level,max_enemy_level\n"
		+ "enemy_chaser,%s,0.1,1,999\n" % gear_mod_id
	)
	_write_text(
		root.path_join("data/strings.csv"),
		"keys,zh_CN,en\n"
		+ "mod_%s_name,\u6d4b\u8bd5\u6a21\u7ec4,Test Mod\n" % package_id
		+ "mod_%s_desc,\u6d4b\u8bd5\u63cf\u8ff0,Test description\n" % package_id
	)
	var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_expect(image.save_png(root.path_join("media/icon.png")) == OK, "%s PNG fixture should save" % package_id)
	_write_wav(root.path_join("media/valid.wav"))
	_write_text(root.path_join("media/broken.ogg"), "not ogg")


func _write_invalid_package() -> void:
	var root: String = TEST_ROOTS[1]
	DirAccess.make_dir_recursive_absolute(root.path_join("data"))
	var manifest: Dictionary = {
		"schema_version": 2,
		"id": "l1_mod_v2_bad",
		"name": "Bad",
		"version": "1.0.0",
		"contract_extensions": {"gear_mod_ids": ["mod_l1_mod_v2_bad_gear"]},
		"data_patches": [
			{
				"type": "json_array_append",
				"target": "gear_mods.json",
				"path": "data/bad.json",
				"array_key": "mods",
			},
		],
	}
	_write_text(root.path_join("mod.json"), JSON.stringify(manifest, "\t"))
	_write_text(
		root.path_join("data/bad.json"),
		JSON.stringify({
			"mods": [
				{
					"id": "mod_l1_mod_v2_bad_gear",
					"name_key": "mod_l1_mod_v2_bad_name",
					"desc_key": "mod_l1_mod_v2_bad_desc",
					"default_unlocked": false,
					"rarity": "common",
					"components": [
						{
							"component_id": "unsafe_program",
							"type": "program",
							"program": {
								"program_id": "unsafe_program",
								"trigger": "skill_activated",
								"conditions": [],
								"actions": [{"action": "mod_custom_action", "params": {}}],
								"proc_chance": 1.0,
								"internal_cooldown": 0.0,
							},
						},
					],
				},
			],
		}, "\t")
	)


func _write_deep_invalid_package() -> void:
	var package_id: String = "l1_mod_v2_deep_bad"
	var root: String = "user://mods/%s" % package_id
	DirAccess.make_dir_recursive_absolute(root.path_join("data"))
	var gear_mod_id: String = "mod_%s_gear" % package_id
	var manifest: Dictionary = {
		"schema_version": 2,
		"id": package_id,
		"name": "Deep Bad",
		"version": "1.0.0",
		"enabled": true,
		"load_order": 50,
		"contract_extensions": {
			"gear_mod_ids": [gear_mod_id],
			"locale_prefixes": ["mod_%s_" % package_id],
		},
		"data_patches": [
			{
				"type": "json_array_append",
				"target": "gear_mods.json",
				"path": "data/gear_mods.json",
				"array_key": "mods",
			},
			{
				"type": "csv_append",
				"target": "gear_mod_drop_tables.csv",
				"path": "data/drops.csv",
			},
			{
				"type": "csv_append",
				"target": "strings.csv",
				"path": "data/strings.csv",
			},
		],
	}
	_write_text(root.path_join("mod.json"), JSON.stringify(manifest, "\t"))
	_write_text(
		root.path_join("data/gear_mods.json"),
		JSON.stringify({
			"mods": [
				{
					"id": gear_mod_id,
					"name_key": "mod_%s_name" % package_id,
					"desc_key": "mod_%s_desc" % package_id,
					"default_unlocked": true,
					"rarity": "common",
					"components": [
						{
							"component_id": "invalid_hero_damage",
							"type": "modifier",
							"slot": "hero",
							"modifiers": [
								{"stat": "damage", "type": "mult", "value": 1.1},
							],
						},
					],
				},
			],
		}, "\t")
	)
	_write_text(
		root.path_join("data/drops.csv"),
		"source_enemy_id,mod_id,drop_chance,min_enemy_level,max_enemy_level\n"
		+ "enemy_chaser,%s,0.2,1,999\n" % gear_mod_id
	)
	_write_text(
		root.path_join("data/strings.csv"),
		"keys,zh_CN,en\n"
		+ "mod_%s_name,\u9519\u8bef\u6a21\u5757,Invalid Mod\n" % package_id
		+ "mod_%s_desc,\u9519\u8bef\u69fd\u4f4d,Invalid slot stat\n" % package_id
	)


func _write_invalid_manifest_package() -> void:
	var root: String = "user://mods/l1_mod_v2_manifest_bad"
	DirAccess.make_dir_recursive_absolute(root)
	_write_text(
		root.path_join("mod.json"),
		JSON.stringify(
			{
				"schema_version": 2,
				"id": "l1_mod_v2_manifest_bad",
				"name": "Manifest Bad",
				"version": "1.0.0",
				"contract_extensions": {},
				"data_patches": [],
				"script_path": "unsafe.gd",
			},
			"\t"
		)
	)


func _write_resource_budget_packages() -> void:
	_write_manifest_budget_package()
	_write_patch_budget_package()
	_write_total_budget_package()
	_write_json_depth_budget_package()
	_write_json_node_budget_package()
	_write_csv_row_budget_package()
	_write_csv_column_budget_package()


func _write_manifest_budget_package() -> void:
	var root: String = TEST_ROOTS[5]
	DirAccess.make_dir_recursive_absolute(root)
	var manifest: Dictionary = _budget_manifest("l1_mod_v2_manifest_budget", [])
	_write_text(
		root.path_join("mod.json"),
		" ".repeat(MOD_LOADER_SCRIPT.MAX_MANIFEST_BYTES) + JSON.stringify(manifest)
	)


func _write_patch_budget_package() -> void:
	var root: String = TEST_ROOTS[6]
	DirAccess.make_dir_recursive_absolute(root.path_join("data"))
	var patches: Array = [_json_budget_patch("data/oversized.json")]
	_write_text(root.path_join("mod.json"), JSON.stringify(_budget_manifest("l1_mod_v2_patch_budget", patches), "\t"))
	_write_text(
		root.path_join("data/oversized.json"),
		" ".repeat(MOD_LOADER_SCRIPT.MAX_GAMEPLAY_PATCH_FILE_BYTES + 1)
	)


func _write_total_budget_package() -> void:
	var root: String = TEST_ROOTS[7]
	DirAccess.make_dir_recursive_absolute(root.path_join("data"))
	var patches: Array = []
	var file_count: int = 5
	var padding_size: int = int(MOD_LOADER_SCRIPT.MAX_GAMEPLAY_PATCH_TOTAL_BYTES / file_count) + 1
	var relative_path: String = "data/reused.json"
	_write_text(
		root.path_join(relative_path),
		" ".repeat(padding_size)
		+ JSON.stringify({"reward_pool_contributions": []})
	)
	for index: int in range(file_count):
		patches.append(_json_budget_patch(relative_path))
	_write_text(root.path_join("mod.json"), JSON.stringify(_budget_manifest("l1_mod_v2_total_budget", patches), "\t"))


func _write_json_depth_budget_package() -> void:
	var root: String = TEST_ROOTS[8]
	DirAccess.make_dir_recursive_absolute(root.path_join("data"))
	_write_text(
		root.path_join("mod.json"),
		JSON.stringify(_budget_manifest("l1_mod_v2_json_depth_budget", [_json_budget_patch("data/deep.json")]), "\t")
	)
	var nesting: int = MOD_LOADER_SCRIPT.MAX_GAMEPLAY_JSON_DEPTH
	_write_text(
		root.path_join("data/deep.json"),
		'{"reward_pool_contributions":' + "[".repeat(nesting) + "0" + "]".repeat(nesting) + "}"
	)


func _write_json_node_budget_package() -> void:
	var root: String = TEST_ROOTS[9]
	DirAccess.make_dir_recursive_absolute(root.path_join("data"))
	_write_text(
		root.path_join("mod.json"),
		JSON.stringify(_budget_manifest("l1_mod_v2_json_node_budget", [_json_budget_patch("data/wide.json")]), "\t")
	)
	var values: PackedStringArray = PackedStringArray()
	values.resize(MOD_LOADER_SCRIPT.MAX_GAMEPLAY_JSON_NODES * 2)
	values.fill("0")
	_write_text(root.path_join("data/wide.json"), '{"reward_pool_contributions":[' + ",".join(values) + "]}")


func _write_csv_row_budget_package() -> void:
	var root: String = TEST_ROOTS[10]
	DirAccess.make_dir_recursive_absolute(root.path_join("data"))
	var patch: Dictionary = {
		"type": "csv_append",
		"target": "strings.csv",
		"path": "data/rows.csv",
	}
	_write_text(root.path_join("mod.json"), JSON.stringify(_budget_manifest("l1_mod_v2_csv_row_budget", [patch]), "\t"))
	var lines: PackedStringArray = PackedStringArray(["keys,zh_CN,en"])
	for index: int in range(MOD_LOADER_SCRIPT.MAX_GAMEPLAY_CSV_ROWS + 1):
		lines.append("mod_l1_mod_v2_csv_row_budget_%d,zh,en" % index)
	_write_text(root.path_join("data/rows.csv"), "\n".join(lines) + "\n")


func _write_csv_column_budget_package() -> void:
	var root: String = TEST_ROOTS[11]
	DirAccess.make_dir_recursive_absolute(root.path_join("data"))
	var patch: Dictionary = {
		"type": "csv_append",
		"target": "strings.csv",
		"path": "data/columns.csv",
	}
	_write_text(root.path_join("mod.json"), JSON.stringify(_budget_manifest("l1_mod_v2_csv_column_budget", [patch]), "\t"))
	var headers: PackedStringArray = PackedStringArray()
	for index: int in range(MOD_LOADER_SCRIPT.MAX_GAMEPLAY_CSV_COLUMNS + 1):
		headers.append("column_%d" % index)
	_write_text(root.path_join("data/columns.csv"), ",".join(headers) + "\n")


func _budget_manifest(package_id: String, patches: Array) -> Dictionary:
	return {
		"schema_version": 2,
		"id": package_id,
		"name": "Budget fixture",
		"version": "1.0.0",
		"contract_extensions": {},
		"data_patches": patches,
	}


func _json_budget_patch(relative_path: String) -> Dictionary:
	return {
		"type": "json_array_append",
		"target": "gear_mods.json",
		"path": relative_path,
		"array_key": "reward_pool_contributions",
	}


func _has_audio(audio_id: String) -> bool:
	return not _audio_entry(audio_id).is_empty()


func _audio_entry(audio_id: String) -> Dictionary:
	for entry: Dictionary in _mod_loader.call("media_audio_entries") as Array[Dictionary]:
		if String(entry.get("id", "")) == audio_id:
			return entry
	return {}


func _diagnostics_contain(fragment: String) -> bool:
	for diagnostic: String in _mod_loader.call("diagnostics") as Array[String]:
		if diagnostic.contains(fragment):
			return true
	return false


func _cleanup() -> void:
	for root: String in TEST_ROOTS:
		_remove_tree(root)


func _remove_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		var child_path: String = path.path_join(entry_name)
		if directory.current_is_dir():
			_remove_tree(child_path)
		else:
			DirAccess.remove_absolute(child_path)
		entry_name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_text(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "%s should be writable" % path)
	if file != null:
		file.store_string(content)


func _write_wav(path: String) -> void:
	const SAMPLE_RATE: int = 8000
	const SAMPLE_COUNT: int = 800
	var bytes := PackedByteArray()
	bytes.resize(44 + SAMPLE_COUNT)
	_write_ascii(bytes, 0, "RIFF")
	bytes.encode_u32(4, 36 + SAMPLE_COUNT)
	_write_ascii(bytes, 8, "WAVE")
	_write_ascii(bytes, 12, "fmt ")
	bytes.encode_u32(16, 16)
	bytes.encode_u16(20, 1)
	bytes.encode_u16(22, 1)
	bytes.encode_u32(24, SAMPLE_RATE)
	bytes.encode_u32(28, SAMPLE_RATE)
	bytes.encode_u16(32, 1)
	bytes.encode_u16(34, 8)
	_write_ascii(bytes, 36, "data")
	bytes.encode_u32(40, SAMPLE_COUNT)
	for index: int in range(SAMPLE_COUNT):
		bytes[44 + index] = 128
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "%s should be writable" % path)
	if file != null:
		file.store_buffer(bytes)


func _write_ascii(bytes: PackedByteArray, offset: int, value: String) -> void:
	var encoded: PackedByteArray = value.to_ascii_buffer()
	for index: int in range(encoded.size()):
		bytes[offset + index] = encoded[index]


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("MOD LOADER V2 SMOKE ALL PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("[mod-loader-v2-smoke] %s" % failure)
	quit(1)


func _reload_packages() -> bool:
	return bool(_mod_loader.call("reload_packages"))
