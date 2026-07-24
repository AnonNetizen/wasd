# Doc: docs/代码/visual_effects.md
class_name GameplayFeedbackController
extends Node
## Presentation-only semantic cue router for the current run.


var _host: VfxHost = null


func _ready() -> void:
	if _host == null:
		_host = get_node_or_null("../VfxHost") as VfxHost


func configure_host(host: VfxHost) -> void:
	_host = host


func play(
		profile_id: String,
		cue: String,
		context: Dictionary = {}
	) -> Array[VfxHandle]:
	var handles: Array[VfxHandle] = []
	if _host == null:
		push_warning("[GameplayFeedbackController] VfxHost is not configured")
		return handles
	var binding: Dictionary = VisualEffects.resolve_binding(profile_id, cue)
	if binding.is_empty():
		return handles

	var raw_effects: Array = binding.get("effects", []) as Array
	for raw_effect: Variant in raw_effects:
		if not raw_effect is Dictionary:
			continue
		var effect_binding: Dictionary = raw_effect as Dictionary
		var effect_id: String = String(effect_binding.get("effect_id", ""))
		if effect_id.is_empty():
			continue
		var effect_context: Dictionary = context.duplicate(true)
		effect_context["anchor"] = String(effect_binding.get("anchor", "center"))
		var raw_params: Variant = effect_binding.get("params", {})
		if raw_params is Dictionary:
			for raw_key: Variant in (raw_params as Dictionary).keys():
				effect_context[raw_key] = (raw_params as Dictionary)[raw_key]
		var handle: VfxHandle = _host.play(
			effect_id,
			VfxPlayRequest.from_context(effect_context)
		)
		if handle != null:
			handles.append(handle)

	var screen_effect_id: String = String(binding.get("screen_effect_id", ""))
	if not screen_effect_id.is_empty():
		var screen_context: Dictionary = context.duplicate(true)
		screen_context["owner"] = null
		var screen_handle: VfxHandle = _host.play(
			screen_effect_id,
			VfxPlayRequest.from_context(screen_context)
		)
		if screen_handle != null:
			handles.append(screen_handle)

	var audio_id: String = String(binding.get("audio_id", ""))
	if not audio_id.is_empty() and AudioManager.has_stream(audio_id):
		AudioManager.play_sfx(audio_id)

	var camera_feedback_id: String = String(binding.get("camera_feedback_id", ""))
	var raw_camera: Variant = context.get("camera_controller")
	if (
		not camera_feedback_id.is_empty()
		and raw_camera is Node
		and (raw_camera as Node).has_method("play_feedback")
	):
		(raw_camera as Node).call("play_feedback", camera_feedback_id)

	# hit_stop_profile_id is intentionally data-visible but not executed in schema v1.
	return handles
