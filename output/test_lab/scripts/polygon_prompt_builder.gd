class_name PolygonPromptBuilder
extends RefCounted

const SUPPORTED_MANIFEST_SCHEMA: int = 3
const SUPPORTED_TEMPLATE_SCHEMA: int = 1


func build_from_manifest(manifest_path: String) -> Dictionary:
	var manifest_result := _load_json_dictionary(manifest_path)
	if not bool(manifest_result.get("ok", false)):
		return manifest_result
	var manifest: Dictionary = manifest_result["data"]
	if (
		int(manifest.get("schema_version", 0))
		!= SUPPORTED_MANIFEST_SCHEMA
	):
		return _failure("Unsupported Polygon manifest schema_version.")
	var template_path := String(manifest.get("prompt_template", ""))
	var template_result := _load_json_dictionary(template_path)
	if not bool(template_result.get("ok", false)):
		return template_result
	var template: Dictionary = template_result["data"]
	if (
		int(template.get("schema_version", 0))
		!= SUPPORTED_TEMPLATE_SCHEMA
	):
		return _failure("Unsupported Polygon prompt template schema_version.")
	var variables_value: Variant = manifest.get("prompt_variables", {})
	if not variables_value is Dictionary:
		return _failure("Manifest prompt_variables must be a dictionary.")
	var variables: Dictionary = (variables_value as Dictionary).duplicate(
		true
	)
	variables["asset_id"] = String(manifest.get("asset_id", ""))
	variables["background_key"] = String(
		manifest.get("background_key", "#ff00ff")
	).to_upper()
	var feature_result := _build_feature_contract(
		manifest.get("feature_guides", [])
	)
	if not bool(feature_result.get("ok", false)):
		return feature_result
	variables["feature_contract"] = String(feature_result["text"])
	var required_value: Variant = template.get("required_variables", [])
	if not required_value is Array:
		return _failure(
			"Prompt template required_variables must be an array."
		)
	for variable_value: Variant in required_value:
		var variable_name := String(variable_value)
		if (
			not variables.has(variable_name)
			or String(variables[variable_name]).strip_edges().is_empty()
		):
			return _failure(
				"Prompt variable is missing or empty: %s." % variable_name
			)
	var sections_value: Variant = template.get("sections", [])
	if not sections_value is Array or (sections_value as Array).is_empty():
		return _failure("Prompt template sections must be a non-empty array.")
	var rendered_sections: PackedStringArray = []
	for section_value: Variant in sections_value:
		var section := String(section_value)
		for variable_value: Variant in variables:
			var variable_name := String(variable_value)
			section = section.replace(
				"{{%s}}" % variable_name,
				String(variables[variable_name])
			)
		if section.contains("{{") or section.contains("}}"):
			return _failure(
				"Prompt template contains an unresolved placeholder."
			)
		rendered_sections.append(section)
	return {
		"ok": true,
		"template_id": String(template.get("template_id", "")),
		"prompt": "\n\n".join(rendered_sections),
		"rejection_checks": template.get(
			"rejection_checks",
			[]
		).duplicate(true),
	}


func _build_feature_contract(guides_value: Variant) -> Dictionary:
	if not guides_value is Array:
		return _failure("Manifest feature_guides must be an array.")
	var guides: Array = guides_value
	if guides.size() != 1:
		return _failure(
			"Prompt authoring schema v1 requires one primary landmark feature."
		)
	var feature_blocks: PackedStringArray = []
	for guide_index in range(guides.size()):
		if not guides[guide_index] is Dictionary:
			return _failure(
				"Manifest feature_guides entries must be dictionaries."
			)
		var guide: Dictionary = guides[guide_index]
		var feature_id := String(guide.get("id", ""))
		var kind := String(guide.get("kind", ""))
		var semantic_role := String(
			guide.get("semantic_role", "")
		)
		var path_description := String(
			guide.get("path_description", "")
		)
		var contrast_description := String(
			guide.get("contrast_description", "")
		)
		var construction_meaning := String(
			guide.get("construction_meaning", "")
		)
		if (
			feature_id.is_empty()
			or kind.is_empty()
			or semantic_role.is_empty()
			or path_description.is_empty()
			or contrast_description.is_empty()
			or construction_meaning.is_empty()
		):
			return _failure(
				"Feature prompt metadata is incomplete: %s."
				% feature_id
			)
		var minimum_width := float(
			guide.get("minimum_constructed_width_px", 0.0)
		)
		var maximum_width := float(
			guide.get("maximum_constructed_width_px", 0.0)
		)
		if minimum_width <= 0.0 or maximum_width < minimum_width:
			return _failure(
				"Feature prompt width range is invalid: %s."
				% feature_id
			)
		feature_blocks.append(
			(
				"Landmark %d\n"
				+ "- id: %s\n"
				+ "- semantic role: %s\n"
				+ "- geometry: %s\n"
				+ "- path: %s\n"
				+ "- readable width: %.0f to %.0f pixels at 256 by 256\n"
				+ "- contrast: %s\n"
				+ "- construction meaning: %s\n"
				+ "- topology: one continuous unbroken band with no "
				+ "branches, duplicate marks, symbols, or decorative ticks"
			)
			% [
				guide_index + 1,
				feature_id,
				semantic_role,
				kind,
				path_description,
				minimum_width,
				maximum_width,
				contrast_description,
				construction_meaning,
			]
		)
	return {
		"ok": true,
		"text": "\n\n".join(feature_blocks),
	}


func _load_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return _failure("JSON file does not exist: %s." % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Failed to open JSON file: %s." % path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return _failure(
			"JSON parse failed for %s at line %d: %s."
			% [
				path,
				parser.get_error_line(),
				parser.get_error_message(),
			]
		)
	var data: Variant = parser.data
	if not data is Dictionary:
		return _failure("JSON root must be a dictionary: %s." % path)
	return {"ok": true, "data": data}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
