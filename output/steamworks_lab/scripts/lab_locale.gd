class_name SteamLabLocale
extends RefCounted

const LOCALE_ZH_CN: String = "zh_CN"
const LOCALE_EN: String = "en"
const SUPPORTED_LOCALES: Array[String] = [LOCALE_ZH_CN, LOCALE_EN]

const TRANSLATIONS: Dictionary = {
	LOCALE_ZH_CN: {
		"app_title": "Steamworks Slime Lab",
		"main_kicker": "STEAM / LOCAL CO-OP LAB",
		"main_subtitle": "软体史莱姆 · 竖版弹幕 · Host 权威联机验证",
		"main_single": "开始单人游戏",
		"main_multiplayer": "开始联机游戏",
		"main_records": "记录",
		"main_settings": "设置",
		"main_hint": "WASD / 方向键移动    鼠标射击    Q 主动道具    T 表情轮    Esc 暂停",
		"ready_room_kicker": "READY ROOM",
		"multiplayer_title": "联机准备",
		"section_session": "会话",
		"section_local": "本地",
		"section_steam": "Steam",
		"section_ready_room": "准备房间",
		"section_status_log": "状态日志",
		"host_local": "创建本地房间",
		"join_local": "加入本地房间",
		"address_placeholder": "地址",
		"steam_lobby_id_placeholder": "Steam lobby id",
		"host_steam": "创建 Steam 房间",
		"join_steam": "通过 ID 加入 Steam",
		"start_battle": "开始战斗",
		"leave_session": "离开会话",
		"back": "返回",
		"settings_kicker": "OPTIONS",
		"settings_title": "设置",
		"settings_language": "语言",
		"settings_fullscreen": "全屏",
		"settings_back": "返回",
		"language_zh_cn": "简体中文",
		"language_en": "English",
		"status_mode": "模式：{mode}\nPeer：{peer}\nLobby：{lobby}\n玩家：{players}",
		"ready_room_empty": "准备房间：当前没有会话。",
		"ready_room_host": "准备房间\n已连接玩家：{players}\n等大家进来后再开始。",
		"ready_room_client": "准备房间\n已作为 peer {peer} 连接\n等待 host 开始。",
		"log_multiplayer_setup": "进入联机设置。",
		"log_single_player_started": "单人游戏已开始。",
		"log_need_two_players": "准备房间至少需要 2 名玩家。",
		"log_ready_room_created": "准备房间已创建。等玩家加入后开始。",
		"log_ready_room_joined": "已加入准备房间，等待 host 开始。",
		"log_session_ready": "会话就绪：{transport} {role}",
		"log_role_host": "host",
		"log_role_client": "client",
		"log_battle_launch": "已从准备房间开始战斗。",
		"log_host_started_battle": "Host 已开始战斗。",
		"log_session_left": "已离开联机会话。",
		"log_returned_start": "已返回主菜单。",
		"log_battle_restarted": "战斗已重开。",
		"log_active_item_used": "Peer {peer} 使用了 {item}。",
		"buff_title_choose": "选择一项强化",
		"buff_title_waiting": "强化选择",
		"buff_waiting": "等待其他玩家选择…",
		"buff_waiting_count": "等待其他玩家选择… ({count})",
		"buff_countdown": "{seconds} 秒后自动选择",
		"hud_empty_item": "空",
		"hud_spectator": "观战中…",
		"pause_title": "暂停",
		"pause_resume": "继续",
		"pause_back_to_menu": "返回主菜单",
		"records_title": "记录",
		"records_best_survival": "最长存活时间",
		"records_no_record": "暂无记录",
		"records_close": "关闭",
		"game_over_title": "全员阵亡",
		"game_over_stats": "存活时间 {time}\nTier {tier} · 击破 Boss {bosses}",
		"restart": "再来一局",
		"leave": "离开",
		"player_down_suffix": " (阵亡)",
		"active_item_fallback": "主动道具",
		"active_repair_wave": "修复波",
		"active_clear_pulse": "清场脉冲",
		"active_stasis_field": "凝滞场",
		"active_team_overload": "团队过载",
		"active_emergency_shield": "应急护膜",
		"buff_fire_rate_name": "射速强化",
		"buff_fire_rate_desc": "开火冷却 ×0.85",
		"buff_damage_name": "弹头强化",
		"buff_damage_desc": "子弹伤害 +1",
		"buff_multi_shot_name": "多重散射",
		"buff_multi_shot_desc": "每次多射出 1 颗子弹",
		"buff_move_speed_name": "机动强化",
		"buff_move_speed_desc": "移动速度 ×1.12",
		"buff_heal_name": "紧急修复",
		"buff_heal_desc": "恢复 1 点生命",
		"buff_bullet_speed_name": "高速弹道",
		"buff_bullet_speed_desc": "子弹速度 ×1.2",
		"buff_pierce_name": "穿透弹芯",
		"buff_pierce_desc": "子弹可再穿透 1 个敌人",
		"emote_happy": "开心",
		"emote_wave": "招呼",
		"emote_surprised": "惊讶",
		"emote_love": "喜欢",
		"emote_angry": "生气",
		"emote_panic": "慌张",
		"emote_ready": "准备",
		"emote_sleepy": "困了",
	},
	LOCALE_EN: {
		"app_title": "Steamworks Slime Lab",
		"main_kicker": "STEAM / LOCAL CO-OP LAB",
		"main_subtitle": "Soft Slimes · Vertical Bullet Hell · Host-Authoritative Netplay",
		"main_single": "Single Player",
		"main_multiplayer": "Multiplayer",
		"main_records": "Records",
		"main_settings": "Settings",
		"main_hint": "WASD / Arrow Keys Move    Mouse Fire    Q Active Item    T Emote Wheel    Esc Pause",
		"ready_room_kicker": "READY ROOM",
		"multiplayer_title": "Multiplayer",
		"section_session": "Session",
		"section_local": "Local",
		"section_steam": "Steam",
		"section_ready_room": "Ready Room",
		"section_status_log": "Status Log",
		"host_local": "Host Local",
		"join_local": "Join Local",
		"address_placeholder": "Address",
		"steam_lobby_id_placeholder": "Steam lobby id",
		"host_steam": "Host Steam",
		"join_steam": "Join Steam by ID",
		"start_battle": "Start Battle",
		"leave_session": "Leave Session",
		"back": "Back",
		"settings_kicker": "OPTIONS",
		"settings_title": "Settings",
		"settings_language": "Language",
		"settings_fullscreen": "Fullscreen",
		"settings_back": "Back",
		"language_zh_cn": "简体中文",
		"language_en": "English",
		"status_mode": "Mode: {mode}\nPeer: {peer}\nLobby: {lobby}\nPlayers: {players}",
		"ready_room_empty": "Ready room: no active session.",
		"ready_room_host": "Ready room\nPlayers connected: {players}\nStart when everyone has joined.",
		"ready_room_client": "Ready room\nConnected as peer {peer}\nWaiting for host to start.",
		"log_multiplayer_setup": "Multiplayer setup.",
		"log_single_player_started": "Single player started.",
		"log_need_two_players": "Need at least 2 players in the ready room.",
		"log_ready_room_created": "Ready room created. Wait for players, then start.",
		"log_ready_room_joined": "Joined ready room. Waiting for host start.",
		"log_session_ready": "Session ready: {transport} {role}",
		"log_role_host": "host",
		"log_role_client": "client",
		"log_battle_launch": "Battle launched from ready room.",
		"log_host_started_battle": "Host started the battle.",
		"log_session_left": "Multiplayer session left.",
		"log_returned_start": "Returned to start page.",
		"log_battle_restarted": "Battle restarted.",
		"log_active_item_used": "Peer {peer} used {item}.",
		"buff_title_choose": "Choose a Boost",
		"buff_title_waiting": "Boost Choice",
		"buff_waiting": "Waiting for other players...",
		"buff_waiting_count": "Waiting for other players... ({count})",
		"buff_countdown": "Auto-pick in {seconds}s",
		"hud_empty_item": "Empty",
		"hud_spectator": "Spectating...",
		"pause_title": "Paused",
		"pause_resume": "Resume",
		"pause_back_to_menu": "Back to Menu",
		"records_title": "Records",
		"records_best_survival": "Best Survival",
		"records_no_record": "No record yet",
		"records_close": "Close",
		"game_over_title": "All Down",
		"game_over_stats": "Survived {time}\nTier {tier} · Bosses {bosses}",
		"restart": "Restart",
		"leave": "Leave",
		"player_down_suffix": " (Down)",
		"active_item_fallback": "Active Item",
		"active_repair_wave": "Repair Wave",
		"active_clear_pulse": "Clear Pulse",
		"active_stasis_field": "Stasis Field",
		"active_team_overload": "Team Overload",
		"active_emergency_shield": "Emergency Shield",
		"buff_fire_rate_name": "Fire Rate Boost",
		"buff_fire_rate_desc": "Fire cooldown ×0.85",
		"buff_damage_name": "Warhead Boost",
		"buff_damage_desc": "Bullet damage +1",
		"buff_multi_shot_name": "Spread Shot",
		"buff_multi_shot_desc": "Fire 1 extra bullet per shot",
		"buff_move_speed_name": "Mobility Boost",
		"buff_move_speed_desc": "Move speed ×1.12",
		"buff_heal_name": "Emergency Repair",
		"buff_heal_desc": "Restore 1 HP",
		"buff_bullet_speed_name": "High-Speed Rounds",
		"buff_bullet_speed_desc": "Bullet speed ×1.2",
		"buff_pierce_name": "Piercing Core",
		"buff_pierce_desc": "Bullets pierce 1 more enemy",
		"emote_happy": "Happy",
		"emote_wave": "Wave",
		"emote_surprised": "Surprised",
		"emote_love": "Love",
		"emote_angry": "Angry",
		"emote_panic": "Panic",
		"emote_ready": "Ready",
		"emote_sleepy": "Sleepy",
	},
}


static func supported_locales() -> Array[String]:
	return SUPPORTED_LOCALES.duplicate()


static func normalize_locale(raw_locale: String) -> String:
	var clean := raw_locale.strip_edges().to_lower().replace("-", "_")
	if clean == "":
		return LOCALE_EN
	if clean == "schinese" or clean == "tchinese" or clean == "chinese":
		return LOCALE_ZH_CN
	if clean.begins_with("zh") or clean.find("_cn") >= 0 or clean.find("_tw") >= 0 or clean.find("_hk") >= 0:
		return LOCALE_ZH_CN
	return LOCALE_EN


static func is_supported(locale: String) -> bool:
	return SUPPORTED_LOCALES.has(locale)


static func text(locale: String, key: String, args: Dictionary = {}) -> String:
	var normalized := locale if is_supported(locale) else LOCALE_EN
	var locale_table: Dictionary = TRANSLATIONS.get(normalized, {})
	var fallback_table: Dictionary = TRANSLATIONS.get(LOCALE_EN, {})
	var value := String(locale_table.get(key, fallback_table.get(key, key)))
	for arg_key in args.keys():
		value = value.replace("{%s}" % str(arg_key), str(args[arg_key]))
	return value


static func language_label(locale: String, display_locale: String) -> String:
	match locale:
		LOCALE_ZH_CN:
			return text(display_locale, "language_zh_cn")
		LOCALE_EN:
			return text(display_locale, "language_en")
		_:
			return locale
