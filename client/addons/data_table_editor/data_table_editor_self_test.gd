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
const TEST_CATALOG: String = TEST_ROOT + "/catalog.json"
const TEST_TRANSACTION: String = TEST_ROOT + "/transaction.json"

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_prepare_test_directory()
	_test_catalog_and_search()
	_test_document_editing()
	_test_property_reference_options()
	_test_column_resize_bounds()
	_test_transaction_guards()
	_test_contract_dry_run()
	_test_headless_validation_bridge()
	_test_skill_preview()
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
					"effect": "skill_effect_damage",
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
					"effect": "skill_effect_damage",
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
			{"path": "nested.effect", "target": "contract:skill_effects"}
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
		document.set_record_value(
			"records", 0, ["nested", "effect"], "skill_effect_apply_status"
		),
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
		reparsed is Dictionary and JSON.stringify(reparsed, "  ", false, true) + "\n" == serialized,
		"JSON serialization is deterministic after a parse round trip"
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


func _test_skill_preview() -> void:
	var skill: Dictionary = {
		"cooldown": 5.0,
		"targeting": {"radius": 100.0},
		"scaling": {"radius_stat": "ability_range"},
		"costs": [],
		"effects": [],
	}
	var preview: String = SKILL_DESCRIPTION_FORMATTER.format_skill(
		"冷却 {cooldown} 秒，范围 {target_radius}",
		skill,
		{"ability_range": 1.5}
	)
	_expect(preview == "冷却 5 秒，范围 150", "skill preview resolves placeholders and scaling")


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
	for path: String in [TEST_JSON, TEST_CATALOG, TEST_TRANSACTION]:
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
