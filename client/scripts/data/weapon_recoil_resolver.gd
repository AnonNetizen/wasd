# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/决策记录.md ADR #165
class_name WeaponRecoilResolver
extends RefCounted
## Resolves one weapon-runtime stat snapshot into deterministic recoil outputs.


const STATS := preload("res://scripts/contracts/stats.gd")


static func resolve(runtime_stats: Dictionary, recoil_model: Dictionary) -> Dictionary:
	var recoil_max: float = maxf(float(recoil_model.get("recoil_max", 0.0)), 0.0)
	var recoil: float = clampf(
		float(runtime_stats.get(STATS.RECOIL, 0.0)),
		0.0,
		recoil_max
	)
	var recoil_ratio: float = (
		recoil / recoil_max
		if recoil_max > 0.0
		else 0.0
	)
	var runtime_spread_cap: float = maxf(
		float(recoil_model.get("runtime_spread_cap", 0.0)),
		0.0
	)
	var spread_angle_max: float = clampf(
		float(runtime_stats.get(STATS.SPREAD_ANGLE_MAX, 0.0)),
		0.0,
		runtime_spread_cap
	)
	var spread_exponent: float = maxf(
		float(recoil_model.get("spread_exponent", 1.0)),
		0.0
	)
	var spread_angle_degrees: float = (
		spread_angle_max * pow(recoil_ratio, spread_exponent)
	)
	var kickback_distance: float = (
		maxf(float(recoil_model.get("kickback_max_distance", 0.0)), 0.0)
		* recoil_ratio
	)
	var kickback_duration: float = maxf(
		float(recoil_model.get("kickback_duration", 0.0)),
		0.0
	)
	var kickback_initial_speed: float = (
		2.0 * kickback_distance / kickback_duration
		if kickback_duration > 0.0
		else 0.0
	)
	var kickback_velocity_cap: float = maxf(
		float(recoil_model.get("kickback_velocity_cap", 0.0)),
		0.0
	)
	kickback_initial_speed = minf(
		kickback_initial_speed,
		kickback_velocity_cap
	)
	return {
		"recoil": recoil,
		"recoil_ratio": recoil_ratio,
		"spread_angle_degrees": spread_angle_degrees,
		"kickback_distance": kickback_distance,
		"kickback_initial_speed": kickback_initial_speed,
		"kickback_duration": kickback_duration,
		"kickback_velocity_cap": kickback_velocity_cap,
	}
