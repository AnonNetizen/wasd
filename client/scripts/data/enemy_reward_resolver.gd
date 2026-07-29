# Doc: docs/代码/enemy_reward_resolver.md
# Authority: docs/决策记录.md ADR #175
class_name EnemyRewardResolver
extends RefCounted
## Pure enemy-gold calculation. Randomness is supplied by the caller.


const SAFE_GOLD_MAX: int = 2_147_483_647


static func resolve(
	reward_config: Dictionary,
	difficulty_coefficient: float,
	monster_value_multiplier: float,
	specialization_multiplier: float,
	spawn_tier: int,
	random_multiplier: float
) -> Dictionary:
	var base_coefficient: float = float(
		reward_config.get("base_coefficient", 0.0)
	)
	var time_growth_per_tier: float = float(
		reward_config.get("time_growth_per_tier", -1.0)
	)
	if (
		not _is_positive_finite(base_coefficient)
		or not _is_positive_finite(difficulty_coefficient)
		or not _is_positive_finite(monster_value_multiplier)
		or not _is_positive_finite(specialization_multiplier)
		or not _is_positive_finite(random_multiplier)
		or not is_finite(time_growth_per_tier)
		or time_growth_per_tier < 0.0
		or spawn_tier < 0
	):
		return {
			"valid": false,
			"gold_reward": 0,
		}

	var time_multiplier: float = (
		1.0 + time_growth_per_tier * float(spawn_tier)
	)
	var raw_reward: float = (
		base_coefficient
		* difficulty_coefficient
		* monster_value_multiplier
		* specialization_multiplier
		* time_multiplier
		* random_multiplier
	)
	if is_nan(raw_reward) or raw_reward <= 0.0:
		return {
			"valid": false,
			"gold_reward": 0,
		}

	var gold_reward: int = SAFE_GOLD_MAX
	if raw_reward < float(SAFE_GOLD_MAX):
		gold_reward = maxi(roundi(raw_reward), 1)
	return {
		"valid": true,
		"gold_reward": gold_reward,
		"base_coefficient": base_coefficient,
		"difficulty_coefficient": difficulty_coefficient,
		"monster_value_multiplier": monster_value_multiplier,
		"specialization_multiplier": specialization_multiplier,
		"spawn_tier": spawn_tier,
		"time_multiplier": time_multiplier,
		"random_multiplier": random_multiplier,
	}


static func _is_positive_finite(value: float) -> bool:
	return is_finite(value) and value > 0.0
