# Doc: docs/代码/phantom_camera.md
# Authority: client/addons/README.md, docs/决策记录.md ADR #148
extends RefCounted


const EDITOR_SEED_MULTIPLIER: int = 1_103_515_245
const EDITOR_SEED_INCREMENT: int = 12_345
const EDITOR_SEED_MASK: int = 0x7fffffff

static var _editor_seed_state: int = 1


static func next_seed() -> int:
	if Engine.is_editor_hint():
		_editor_seed_state = (
			_editor_seed_state * EDITOR_SEED_MULTIPLIER + EDITOR_SEED_INCREMENT
		) & EDITOR_SEED_MASK
		return _editor_seed_state
	return int(RNG.camera_fx.randi())
