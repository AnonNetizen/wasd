# Doc: docs/代码/data_table_editor.md
extends SceneTree
## Isolated regression suite for the editor-only data table models and index.

const DATA_TABLE_CATALOG := preload("res://scripts/editor/data_table_catalog.gd")
const DATA_TABLE_DOCUMENT := preload("res://scripts/editor/data_table_document.gd")
const DATA_SEARCH_INDEX := preload("res://scripts/editor/data_search_index.gd")
const DATA_TABLE_TRANSACTION := preload("res://scripts/editor/data_table_transaction.gd")
const DATA_TABLE_PROPERTY_EDITOR := preload(
	"res://addons/data_table_editor/data_table_property_editor.gd"
)
const DATA_TABLE_MAIN_SCREEN := preload(
	"res://addons/data_table_editor/data_table_editor_main_screen.gd"
)
const DATA_TABLE_TREE_COLUMN_RESIZER := preload(
	"res://addons/data_table_editor/data_table_tree_column_resizer.gd"
)
const DATA_TABLE_CONTRACT_BRIDGE := preload(
	"res://scripts/editor/data_table_contract_bridge.gd"
)
const PROJECT_DATA_VALIDATION_BRIDGE := preload(
	"res://scripts/editor/project_data_validation_bridge.gd"
)
const SKILL_DESCRIPTION_FORMATTER := preload(
	"res://scripts/data/skill_description_formatter.gd"
)

const TEST_ROOT: String = "user://data_table_editor_self_test"
const TEST_JSON: String = TEST_ROOT + "/fixture.json"
const TEST_FORMATTED_JSON: String = TEST_ROOT + "/formatted_fixture.json"
const TEST_CSV: String = TEST_ROOT + "/fixture.csv"
const TEST_BAD_CSV: String = TEST_ROOT + "/invalid.csv"
const TEST_CATALOG: String = TEST_ROOT + "/catalog.json"
const TEST_TRANSACTION: String = TEST_ROOT + "/transaction.json"
const TEST_GEAR_JSON: String = TEST_ROOT + "/gear_fixture.json"

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_prepare_test_directory()
	_test_catalog_and_search()
	_test_document_editing()
	_test_json_serialization_stability()
	_test_csv_serialization_stability()
	_test_property_reference_options()
	_test_column_resize_bounds()
	_test_transaction_guards()
	_test_contract_dry_run()
	_test_headless_validation_bridge()
	_test_skill_preview()
	_test_gear_mod_editor_contracts()
	_cleanup()
	if _failures.is_empty():
		print("[data-table-editor-smoke] ALL PASS")
		quit(0)
		return
	for failure: String in _failures:
		printerr("[data-table-editor-smoke] %s" % failure)
	quit(1)


func _test_catalog_and_search() -> void:
	var project_file: FileAccess = FileAccess.open("res://project.godot", FileAccess.READ)
	var project_text: String = project_file.get_as_text() if project_file != null else ""
	_expect(
		project_text.contains("res://addons/data_table_editor/plugin.cfg"),
		"data-table plugin is enabled in project.godot"
	)
	var export_file: FileAccess = FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	var export_text: String = export_file.get_as_text() if export_file != null else ""
	_expect(
		export_text.contains("addons/data_table_editor/*"),
		"release preset excludes the data-table plugin"
	)
	var catalog := DATA_TABLE_CATALOG.new() as DataTableCatalog
	var catalog_result: Dictionary = catalog.load_catalog()
	_expect_ok(catalog_result, "catalog loads and covers every project data source")
	if not bool(catalog_result.get("ok", false)):
		return
	var gear_descriptor: Dictionary = catalog.dataset_by_id("gear_mods")
	_expect(
		(gear_descriptor.get("component_templates", []) as Array).size() == 3,
		"gear mod catalog exposes all three component templates"
	)
	_expect(
		gear_descriptor.get("slot_stat_support", {}) is Dictionary,
		"gear mod catalog exposes slot-stat support"
	)
	var skill_descriptor: Dictionary = catalog.dataset_by_id("skills")
	_expect(
		JSON.stringify(skill_descriptor.get("references", [])).contains(
			"programs[].actions[].action"
		),
		"skill catalog references v3 program actions"
	)
	var index := DATA_SEARCH_INDEX.new() as DataSearchIndex
	var rebuild: Dictionary = index.rebuild(catalog)
	_expect_ok(rebuild, "search index rebuilds")
	_expect(int(rebuild.get("entry_count", 0)) > 500, "search index contains flattened fields")
	var exact: Array[Dictionary] = index.query("skill_aoe_slow")
	_expect(not exact.is_empty(), "exact skill id is searchable")
	if not exact.is_empty():
		_expect(int(exact[0].get("score", 99)) == 0, "exact id is ranked first")
	var chinese: Array[Dictionary] = index.query("镇静脉冲")
	_expect(not chinese.is_empty(), "linked Chinese locale text is searchable")
	var multi_term: Array[Dictionary] = index.query("skill cooldown")
	_expect(not multi_term.is_empty(), "space-separated search uses AND terms")
	var csv_number: Array[Dictionary] = index.query("110.0", "enemies", "csv", "number")
	_expect(not csv_number.is_empty(), "CSV numeric cells participate in the number filter")
	for entry: Dictionary in index.entries():
		var path: String = String(entry.get("source_path", ""))
		_expect(not path.contains("/modules/"), "module JSON is excluded from search")
		_expect(not path.ends_with("module_templates.json"), "module registry is excluded from search")
		_expect(not path.ends_with("module_tile_catalog.json"), "tile catalog is excluded from search")
		_expect(not path.ends_with("visual_effects.json"), "VFX catalog is excluded from search")
		_expect(not path.ends_with("presentation_profiles.json"), "profiles are excluded from search")
	_test_deep_search(catalog)


func _test_deep_search(base_catalog: DataTableCatalog) -> void:
	var deep_payload: Dictionary = {
		"records": [
			{
				"id": "deep_record",
				"variants": [
					{
						"kind": "alpha",
						"level_1": {
							"level_2": {
								"level_3": {
									"level_4": {
										"level_5": {"needle": 987654}
									}
								}
							}
						},
					},
					{"kind": "beta", "enabled": true},
				],
			}
		]
	}
	_write_text(TEST_JSON, JSON.stringify(deep_payload, "  ") + "\n")
	var catalog_file: FileAccess = FileAccess.open(
		"res://addons/data_table_editor/data_table_catalog.json", FileAccess.READ
	)
	var catalog_payload: Dictionary = JSON.parse_string(catalog_file.get_as_text()) as Dictionary
	var datasets: Array = catalog_payload.get("datasets", []) as Array
	datasets.append(
		{
			"id": "deep_fixture",
			"label": "深层测试",
			"group": "测试",
			"path": TEST_JSON,
			"format": "json",
			"sections": [{"path": "records", "primary_keys": ["id"]}],
		}
	)
	_write_text(TEST_CATALOG, JSON.stringify(catalog_payload, "  ") + "\n")
	var deep_catalog := DATA_TABLE_CATALOG.new() as DataTableCatalog
	deep_catalog.catalog_path = TEST_CATALOG
	_expect_ok(deep_catalog.load_catalog(), "synthetic deep catalog loads")
	var deep_index := DATA_SEARCH_INDEX.new() as DataSearchIndex
	_expect_ok(deep_index.rebuild(deep_catalog), "deep search index rebuilds")
	var numeric: Array[Dictionary] = deep_index.query("987654", "deep_fixture")
	_expect(not numeric.is_empty(), "numeric value at depth eight is searchable")
	var polymorphic: Array[Dictionary] = deep_index.query("beta true", "deep_fixture")
	_expect(not polymorphic.is_empty(), "polymorphic array fields are searchable with AND")
	var json_only: Array[Dictionary] = deep_index.query("deep_record", "", "json", "string")
	_expect(not json_only.is_empty(), "format and value-type filters compose")
	var _unused: Array[Dictionary] = base_catalog.datasets()


func _test_document_editing() -> void:
	var payload: Dictionary = {
		"schema_version": 1,
		"records": [
			{
				"id": "fixture_a",
				"name_key": "skill_aoe_slow_name",
				"desc_key": "skill_aoe_slow_desc",
				"power": 2.5,
				"nested": {
					"enabled": true,
					"effect": "damage",
					"values": [1, 2],
				},
			},
			{
				"id": "fixture_b",
				"name_key": "skill_aoe_slow_name",
				"desc_key": "skill_aoe_slow_desc",
				"power": 3.0,
				"nested": {
					"enabled": false,
					"effect": "damage",
					"values": [3],
				},
			},
		],
		"pairs": [
			{"left": "a", "right": "b", "value": 1},
			{"left": "a", "right": "", "value": 2},
		],
	}
	_write_text(TEST_JSON, JSON.stringify(payload, "  ") + "\n")
	var descriptor: Dictionary = {
		"id": "document_fixture",
		"label": "文档测试",
		"path": TEST_JSON,
		"format": "json",
		"sections": [
			{"path": "records", "primary_keys": ["id"]},
			{"path": "pairs", "primary_keys": ["left", "right"]},
		],
		"locale_fields": ["name_key", "desc_key"],
		"field_rules": [{"path": "power", "type": "number", "min": 0.0}],
		"references": [
			{"path": "nested.effect", "target": "contract:effect_actions"}
		],
	}
	var document := DATA_TABLE_DOCUMENT.new() as DataTableDocument
	_expect_ok(document.open_dataset(descriptor), "document fixture opens")
	_expect(document.records("records").size() == 2, "document exposes section records")
	_expect(
		not document.set_record_value("records", 0, ["power"], "-1"),
		"declared field range rejects invalid values"
	)
	_expect(
		not document.set_record_value("records", 0, ["power"], "not-a-number"),
		"typed numeric fields reject malformed text"
	)
	_expect(
		not document.set_record_value("records", 0, ["nested", "effect"], "custom_effect"),
		"code primitive references reject unregistered values"
	)
	_expect(not document.has_undo(), "rejected edits do not create empty undo history")
	_expect(
		document.set_record_value("records", 0, ["nested", "effect"], "apply_status"),
		"code primitive references accept registered values"
	)
	_expect(
		document.set_record_value("records", 0, ["nested", "enabled"], "false"),
		"recursive boolean field edits"
	)
	_expect(
		not document.set_record_value("records", 0, ["id"], "renamed"),
		"existing primary id cannot be renamed"
	)
	_expect(document.append_array_value("records", 0, ["nested", "values"]), "array item appends")
	_expect(document.remove_array_value("records", 0, ["nested", "values"], 0), "array item removes")
	var copied_index: int = document.append_record("records", "fixture_c", 0)
	_expect(copied_index == 2, "record copies to a new id")
	_expect(document.record_identity("records", copied_index) == "fixture_c", "copied id is applied")
	_expect(document.append_record("records", "fixture_c", 0) == -1, "duplicate primary id is rejected")
	var copied_pair_index: int = document.append_record("pairs", "c/d", 0)
	_expect(copied_pair_index == 2, "composite-key record copies with replacement keys")
	_expect(
		document.record_identity("pairs", copied_pair_index) == "c/d",
		"composite-key identity uses every configured key"
	)
	_expect(
		document.append_record("pairs", "c/d", 0) == -1,
		"duplicate composite key is rejected during creation"
	)
	_expect(
		document.delete_record(
			"records",
			copied_index,
			PackedStringArray(["fixture_c_name", "fixture_c_desc"])
		),
		"record and explicitly unreferenced locale rows delete"
	)
	_expect(document.locale_value("fixture_c_desc", "zh_CN").is_empty(), "exclusive locale row is removed")
	_expect(document.undo(), "undo restores delete")
	_expect(document.redo(), "redo reapplies delete")
	_expect(
		not document.set_record_value("pairs", 1, ["right"], "b"),
		"duplicate composite primary key is rejected"
	)
	var tsv_result: Dictionary = document.paste_tsv(
		"records", 0, [["power"]], "9.25\n8.5"
	)
	_expect_ok(tsv_result, "TSV paste edits multiple rows")
	_expect(is_equal_approx(float(document.record("records", 1).get("power", 0.0)), 8.5), "TSV preserves numeric type")
	var invalid_tsv: Dictionary = document.paste_tsv(
		"records", 0, [["power"]], "bad-number"
	)
	_expect(not bool(invalid_tsv.get("ok", false)), "invalid TSV input is rejected")
	_expect(
		is_equal_approx(float(document.record("records", 0).get("power", 0.0)), 9.25),
		"invalid TSV paste rolls back every cell"
	)
	_expect(
		document.set_locale_value("skill_aoe_slow_desc", "zh_CN", "测试 {cooldown}"),
		"linked locale value edits in the same document"
	)
	var serialized: String = document.source_text()
	var reparsed: Variant = JSON.parse_string(serialized)
	_expect(
		reparsed is Dictionary and document.source_text() == serialized,
		"JSON serialization is valid and deterministic"
	)
	_expect(document.draft_status() == "matching", "dirty document writes a hash-bound draft")
	var recovered := DATA_TABLE_DOCUMENT.new() as DataTableDocument
	_expect_ok(recovered.open_dataset(descriptor), "recovery document opens")
	_expect_ok(recovered.restore_draft(), "matching draft restores")
	_expect(recovered.dirty, "restored draft remains unsaved")
	_write_text(TEST_JSON, JSON.stringify({"schema_version": 1, "records": []}, "  ") + "\n")
	_expect(document.disk_changed(), "external source change is detected")
	var external_draft_status: String = document.draft_status()
	_expect(
		external_draft_status == "conflict",
		"draft source hashes expose external conflicts (actual: %s)" % external_draft_status
	)
	_expect(
		not bool(document.restore_draft().get("ok", false)),
		"conflicting drafts require explicit replacement approval"
	)
	_expect_ok(document.restore_draft(true), "explicit approval restores a conflicting draft")
	document.discard_draft()
	recovered.discard_draft()


func _test_json_serialization_stability() -> void:
	var original: String = (
		"{\n"
		+ "  \"schema_version\": 1,\n"
		+ "  \"active_items\": [\n"
		+ "    {\n"
		+ "      \"id\": \"active_item_fixture\",\n"
		+ "      \"tags\": [\"tag_active_item\", \"tag_fixture\"],\n"
		+ "      \"charge\": {\n"
		+ "        \"mode\": \"cooldown\",\n"
		+ "        \"cooldown\": 8.0,\n"
		+ "        \"max_charges\": 1,\n"
		+ "        \"start_charges\": 1\n"
		+ "      }\n"
		+ "    }\n"
		+ "  ]\n"
		+ "}\n"
	)
	_write_text(TEST_FORMATTED_JSON, original)
	var descriptor: Dictionary = {
		"id": "json_stability_fixture",
		"label": "JSON 稳定性测试",
		"path": TEST_FORMATTED_JSON,
		"format": "json",
		"sections": [{"path": "active_items", "primary_keys": ["id"]}],
	}
	var document := DATA_TABLE_DOCUMENT.new() as DataTableDocument
	_expect_ok(document.open_dataset(descriptor), "JSON stability fixture opens")
	_expect(
		document.source_text() == original,
		"opening an untouched JSON document produces no synthetic diff"
	)
	var payload: Dictionary = document.data as Dictionary
	var record: Dictionary = (payload.get("active_items", []) as Array)[0] as Dictionary
	var charge: Dictionary = record.get("charge", {}) as Dictionary
	_expect(typeof(payload.get("schema_version")) == TYPE_INT, "JSON integer tokens remain integers")
	_expect(typeof(charge.get("max_charges")) == TYPE_INT, "nested JSON integers remain integers")
	_expect(typeof(charge.get("cooldown")) == TYPE_FLOAT, "JSON decimal tokens remain floats")
	var legacy_data: Dictionary = payload.duplicate(true)
	legacy_data["schema_version"] = 1.0
	var legacy_record: Dictionary = (legacy_data["active_items"] as Array)[0] as Dictionary
	var legacy_charge: Dictionary = legacy_record["charge"] as Dictionary
	legacy_charge["max_charges"] = 1.0
	legacy_charge["start_charges"] = 1.0
	var legacy_draft_path: String = "user://data_table_editor/drafts/json_stability_fixture.json"
	_write_text(
		legacy_draft_path,
		JSON.stringify(
			{
				"schema_version": 1,
				"dataset_id": "json_stability_fixture",
				"source_hash": FileAccess.get_sha256(TEST_FORMATTED_JSON),
				"locale_hash": FileAccess.get_sha256("res://locale/strings.csv"),
				"data": legacy_data,
				"csv_headers": [],
				"locale_rows": document.locale_rows,
				"locale_headers": Array(document.locale_headers),
				"pending_contract_changes": [],
			}
		)
	)
	_expect_ok(document.restore_draft(), "legacy JSON draft restores")
	var restored_payload: Dictionary = document.data as Dictionary
	var restored_record: Dictionary = (
		(restored_payload.get("active_items", []) as Array)[0] as Dictionary
	)
	var restored_charge: Dictionary = restored_record.get("charge", {}) as Dictionary
	_expect(
		typeof(restored_payload.get("schema_version")) == TYPE_INT
		and typeof(restored_charge.get("max_charges")) == TYPE_INT,
		"legacy JSON drafts recover source integer types"
	)
	_expect(
		document.source_text() == original,
		"legacy JSON draft migration removes numeric formatting noise"
	)
	document.discard_draft()
	_expect_ok(document.open_dataset(descriptor), "JSON fixture reopens after legacy draft migration")
	_expect(
		document.set_record_value("active_items", 0, ["charge", "cooldown"], "8.0"),
		"no-op JSON decimal edit is accepted"
	)
	_expect(not document.dirty, "no-op JSON edit does not create a dirty draft")
	_expect(not document.has_undo(), "no-op JSON edit does not create undo history")
	_expect(
		document.set_record_value("active_items", 0, ["charge", "cooldown"], "9.0"),
		"JSON decimal edit succeeds"
	)
	var expected: String = original.replace("\"cooldown\": 8.0", "\"cooldown\": 9.0")
	_expect(
		document.source_text() == expected,
		"JSON editing changes only the intended value and preserves source layout"
	)
	document.discard_draft()


func _test_transaction_guards() -> void:
	_write_text(TEST_TRANSACTION, "before\n")
	var stale_hash: String = FileAccess.get_sha256(TEST_TRANSACTION)
	_write_text(TEST_TRANSACTION, "external\n")
	var conflict: Dictionary = DATA_TABLE_TRANSACTION.commit_texts(
		{TEST_TRANSACTION: "draft\n"}, {TEST_TRANSACTION: stale_hash}
	)
	_expect(not bool(conflict.get("ok", false)), "hash conflict blocks silent overwrite")
	_expect(_read_text(TEST_TRANSACTION) == "external\n", "hash conflict preserves external file")
	var rollback: Dictionary = DATA_TABLE_TRANSACTION.commit_texts(
		{TEST_TRANSACTION: "draft\n"},
		{TEST_TRANSACTION: FileAccess.get_sha256(TEST_TRANSACTION)},
		[],
		Callable(self, "_failing_transaction_hook")
	)
	_expect(not bool(rollback.get("ok", false)), "failing transaction hook rejects save")
	_expect(_read_text(TEST_TRANSACTION) == "external\n", "failed transaction rolls all files back")


func _test_csv_serialization_stability() -> void:
	var locale_descriptor: Dictionary = {
		"id": "locale_csv_regression",
		"label": "文案 CSV 回归",
		"path": "res://locale/strings.csv",
		"format": "csv",
		"primary_keys": ["keys"],
	}
	var locale_document := DATA_TABLE_DOCUMENT.new() as DataTableDocument
	_expect_ok(locale_document.open_dataset(locale_descriptor), "project locale CSV opens")
	_expect(
		locale_document.source_text() == _read_text("res://locale/strings.csv"),
		"opening the project locale CSV produces no synthetic diff"
	)
	_expect(
		locale_document.locale_value("ui_credits_usage_editor_ide", "en")
		== "Godot script editor tabs, outline, and quick-open workflow",
		"project locale CSV preserves English text after embedded commas"
	)
	var original: String = (
		"keys,zh_CN,en\n"
		+ "alpha,甲,\"Quoted without a comma.\"\n"
		+ "beta,乙,\"Text with, a comma.\"\n"
	)
	_write_text(TEST_CSV, original)
	var descriptor: Dictionary = {
		"id": "csv_stability_fixture",
		"label": "CSV 稳定性测试",
		"path": TEST_CSV,
		"format": "csv",
		"primary_keys": ["keys"],
	}
	var document := DATA_TABLE_DOCUMENT.new() as DataTableDocument
	_expect_ok(document.open_dataset(descriptor), "CSV stability fixture opens")
	_expect(document.source_text() == original, "untouched CSV remains byte-for-byte stable")
	_expect(
		document.set_record_value("$rows", 0, ["en"], "Quoted without a comma."),
		"no-op CSV edit is accepted"
	)
	_expect(not document.dirty, "no-op CSV edit does not create a dirty draft")
	_expect(not document.has_undo(), "no-op CSV edit does not create undo history")
	_expect(
		document.set_locale_value(
			"skill_aoe_slow_desc",
			"en",
			document.locale_value("skill_aoe_slow_desc", "en")
		),
		"no-op linked locale edit is accepted"
	)
	_expect(not document.dirty, "no-op linked locale edit stays clean")
	_expect(not document.has_undo(), "no-op linked locale edit creates no undo history")
	_expect(
		document.set_record_value("$rows", 1, ["zh_CN"], "乙改"),
		"CSV value edit succeeds"
	)
	var modified: String = document.source_text()
	_expect(
		modified.contains("alpha,甲,\"Quoted without a comma.\"\n"),
		"untouched CSV rows preserve their original quoting"
	)
	_expect(
		modified.contains("beta,乙改,\"Text with, a comma.\"\n"),
		"changed CSV rows retain comma-bearing cell content"
	)
	document.discard_draft()
	_write_text(TEST_BAD_CSV, "keys,zh_CN,en\nbad,坏,Needs, quoting\n")
	var invalid_descriptor: Dictionary = descriptor.duplicate(true)
	invalid_descriptor["id"] = "invalid_csv_fixture"
	invalid_descriptor["path"] = TEST_BAD_CSV
	var invalid_document := DATA_TABLE_DOCUMENT.new() as DataTableDocument
	_expect(
		not bool(invalid_document.open_dataset(invalid_descriptor).get("ok", false)),
		"CSV rows with unquoted extra columns fail instead of truncating data"
	)


func _test_property_reference_options() -> void:
	var editor := DATA_TABLE_PROPERTY_EDITOR.new() as DataTablePropertyEditor
	root.add_child(editor)
	editor.refresh(
		{"effects": [{"effect": "damage"}]},
		{"effects[].effect": PackedStringArray(["damage", "heal"])},
	)
	var options: PackedStringArray = editor.call(
		"_options_for_path", ["effects", 0, "effect"]
	) as PackedStringArray
	_expect(options == PackedStringArray(["damage", "heal"]), "contract references become field options")
	editor.queue_free()


func _test_column_resize_bounds() -> void:
	var regular: Vector2i = DATA_TABLE_MAIN_SCREEN.resolve_resized_column_pair(
		220, 500, 100
	)
	_expect(regular == Vector2i(320, 400), "column drag resizes adjacent columns")
	var right_limited: Vector2i = DATA_TABLE_MAIN_SCREEN.resolve_resized_column_pair(
		220, 500, 1_000
	)
	_expect(
		right_limited == Vector2i(632, 88),
		"column drag preserves the right-column minimum width"
	)
	var left_limited: Vector2i = DATA_TABLE_MAIN_SCREEN.resolve_resized_column_pair(
		220, 500, -1_000
	)
	_expect(
		left_limited == Vector2i(88, 632),
		"column drag preserves the left-column minimum width"
	)
	var property_limited: Vector2i = DATA_TABLE_TREE_COLUMN_RESIZER.resolve_resized_column_pair(
		144, 260, -1_000, 64
	)
	_expect(
		property_limited == Vector2i(64, 340),
		"recursive property columns use the reusable resizer and their own minimum"
	)
	var panel_split := HSplitContainer.new()
	DATA_TABLE_MAIN_SCREEN.configure_panel_splitter(panel_split)
	_expect(panel_split.dragging_enabled, "outer panel splitters keep dragging enabled")
	_expect(
		panel_split.get_theme_constant(&"minimum_grab_thickness") == 16,
		"outer panel splitters expose a wide drag hit area"
	)
	_expect(
		panel_split.get_theme_constant(&"autohide") == 0,
		"outer panel split grabbers stay visible"
	)
	panel_split.free()


func _test_skill_preview() -> void:
	var skill: Dictionary = {
		"cooldown": 5.0,
		"targeting": {"radius": 100.0},
		"scaling": {
			"radius_stat": "ability_range",
			"strength_stat": "ability_strength",
		},
		"costs": [],
		"programs": [
			{
				"program_id": "preview_program",
				"trigger": "skill_activated",
				"conditions": [],
				"actions": [
					{"action": "heal", "params": {"amount": 20.0}}
				],
				"proc_chance": 1.0,
				"internal_cooldown": 0.0,
			}
		],
	}
	var preview: String = SKILL_DESCRIPTION_FORMATTER.format_skill(
		"冷却 {cooldown} 秒，范围 {target_radius}，治疗 {program_1_action_1_amount}",
		skill,
		{"ability_range": 1.5, "ability_strength": 1.5}
	)
	_expect(
		preview == "冷却 5 秒，范围 150，治疗 30",
		"skill v3 preview resolves program action placeholders and scaling"
	)


func _test_gear_mod_editor_contracts() -> void:
	var payload: Dictionary = {
		"mods": [
			{
				"id": "gear_mod_fixture",
				"components": [
					{
						"component_id": "weapon_modifier",
						"type": "modifier",
						"slot": "weapon",
						"modifiers": [
							{"stat": "damage", "type": "mult", "value": 1.2}
						],
					},
					{
						"component_id": "hero_modifier",
						"type": "modifier",
						"slot": "hero",
						"modifiers": [
							{"stat": "max_hp", "type": "add", "value": 10.0}
						],
					},
				],
			}
		]
	}
	_write_text(TEST_GEAR_JSON, JSON.stringify(payload, "  ") + "\n")
	var descriptor: Dictionary = {
		"id": "gear_mod_fixture",
		"path": TEST_GEAR_JSON,
		"format": "json",
		"sections": [{"path": "mods", "primary_keys": ["id"]}],
		"slot_stat_support": {
			"hero": ["max_hp", "move_speed"],
			"weapon": ["damage", "fire_rate"],
		},
	}
	var document := DATA_TABLE_DOCUMENT.new() as DataTableDocument
	_expect_ok(document.open_dataset(descriptor), "gear mod fixture opens")
	_expect(
		not document.set_record_value(
			"mods", 0, ["components", 0, "modifiers", 0, "stat"], "max_hp"
		),
		"weapon slot rejects hero-only stat"
	)
	_expect(
		not document.set_record_value("mods", 0, ["components", 0, "slot"], "hero"),
		"slot change rejects existing incompatible modifiers"
	)
	_expect(
		document.set_record_value(
			"mods", 0, ["components", 0, "modifiers", 0, "stat"], "fire_rate"
		),
		"weapon slot accepts supported stat"
	)
	_expect(
		not document.set_record_value(
			"mods", 0, ["components", 1, "modifiers", 0, "stat"], "damage"
		),
		"hero slot rejects weapon-only stat"
	)
	var board_template: Dictionary = {
		"component_id": "board_rule_1",
		"type": "board_rule",
		"rule_id": "occupy_only",
	}
	_expect(
		document.append_array_value_from_template(
			"mods", 0, ["components"], board_template
		),
		"catalog component template appends as a deep copy"
	)
	board_template["rule_id"] = "changed_after_append"
	var inserted_record: Dictionary = document.record("mods", 0)
	var inserted_components: Array = inserted_record.get("components", []) as Array
	var appended: Dictionary = inserted_components[2] as Dictionary
	_expect(
		String(appended.get("rule_id", "")) == "occupy_only",
		"component template insertion does not alias catalog data"
	)
	var preview_record: Dictionary = document.record("mods", 0).duplicate(true)
	var preview_components: Array = preview_record.get("components", []) as Array
	preview_components.append(
		{
			"component_id": "trigger_program",
			"type": "program",
			"program": {
				"program_id": "heal_on_damage",
				"trigger": "damage_taken",
				"conditions": [{"condition": "health_ratio", "params": {}}],
				"actions": [{"action": "heal", "params": {"amount": 5.0}}],
				"proc_chance": 0.5,
				"internal_cooldown": 2.0,
			},
		}
	)
	var zh_preview: String = DATA_TABLE_MAIN_SCREEN.format_gear_mod_preview(
		preview_record, "zh_CN"
	)
	var en_preview: String = DATA_TABLE_MAIN_SCREEN.format_gear_mod_preview(
		preview_record, "en"
	)
	_expect(
		zh_preview.contains("heal_on_damage")
		and zh_preview.contains("触发 damage_taken")
		and zh_preview.contains("heal(amount=5)"),
		"gear mod preview renders structured Chinese program details"
	)
	_expect(
		en_preview.contains("conditions") and en_preview.contains("occupy_only"),
		"gear mod preview renders structured English component details"
	)


func _test_contract_dry_run() -> void:
	var before_hash: String = FileAccess.get_sha256(
		ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join(
			"docs/词表与契约.md"
		)
	)
	var valid: Dictionary = DATA_TABLE_CONTRACT_BRIDGE.validate_changes(
		[
			{
				"action": "register",
				"contract_key": "skill_ids",
				"id": "skill_data_table_editor_smoke",
				"meaning": "数据配表 smoke",
			}
		]
	)
	_expect_ok(valid, "controlled contract dry-run accepts an allowlisted content id")
	var invalid: Dictionary = DATA_TABLE_CONTRACT_BRIDGE.validate_changes(
		[
			{
				"action": "register",
				"contract_key": "skill_effects",
				"id": "skill_effect_editor_forbidden",
				"meaning": "forbidden primitive",
			}
		]
	)
	_expect(not bool(invalid.get("ok", false)), "contract wizard rejects code primitives")
	var after_hash: String = FileAccess.get_sha256(
		ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join(
			"docs/词表与契约.md"
		)
	)
	_expect(before_hash == after_hash, "contract dry-run does not modify authority files")


func _test_headless_validation_bridge() -> void:
	var result: Dictionary = PROJECT_DATA_VALIDATION_BRIDGE.validate_project_data(true)
	_expect_ok(result, "shared headless DataLoader validation bridge succeeds")


func _failing_transaction_hook() -> Dictionary:
	return {"ok": false, "errors": PackedStringArray(["intentional rollback"])}


func _prepare_test_directory() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ROOT))


func _cleanup() -> void:
	for path: String in [
		TEST_JSON,
		TEST_FORMATTED_JSON,
		TEST_CSV,
		TEST_BAD_CSV,
		TEST_CATALOG,
		TEST_TRANSACTION,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute_root: String = ProjectSettings.globalize_path(TEST_ROOT)
	if DirAccess.dir_exists_absolute(absolute_root):
		DirAccess.remove_absolute(absolute_root)


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("failed to write fixture: %s" % path)
		return
	file.store_string(text)
	file.close()


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _expect_ok(result: Dictionary, label: String) -> void:
	if bool(result.get("ok", false)):
		return
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	_failures.append("%s: %s" % [label, "; ".join(errors)])


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
