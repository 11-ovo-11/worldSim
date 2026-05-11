extends RefCounted
class_name GameVisualUtils

static func build_location_visual_hint(site_name: String, cn_desc: String) -> String:
	var merged = (site_name + " " + cn_desc).strip_edges()
	if merged.find("食堂") != -1:
		return "communal dining hall, food counters, tables, era-consistent props"
	if merged.find("图书馆") != -1:
		return "library interior, bookshelves, reading area, quiet atmosphere"
	if merged.find("宿舍") != -1:
		return "residential quarters, corridor doors, daily-life details matching era"
	if merged.find("操场") != -1 or merged.find("体育") != -1:
		return "training ground or sports field, open area with active movement"
	if merged.find("教室") != -1 or merged.find("教学楼") != -1:
		return "learning hall interior, teaching space, era-appropriate furniture"
	if merged.find("超市") != -1 or merged.find("小卖部") != -1:
		return "general goods shop or market stall, goods display aligned with era"
	if merged.find("校门") != -1:
		return "main gate area, checkpoints and passers-by matching setting"
	return "architecture and props consistent with current world setting and era"

static func build_cn_desc_visual_anchor(cn_desc: String) -> String:
	var desc = cn_desc.strip_edges()
	if desc == "":
		return ""
	var keyword_map = {
		"跑道": "running track",
		"足球场": "football field",
		"篮球场": "basketball court",
		"看台": "stadium stands",
		"草坪": "open grass field",
		"健身": "sports training atmosphere",
		"图书馆": "library interior",
		"书架": "bookshelves",
		"自习": "study desks and lamps",
		"食堂": "cafeteria serving counters",
		"宿舍": "dormitory corridor",
		"教学楼": "teaching building corridor",
		"教室": "classroom interior",
		"超市": "convenience store shelves",
		"小卖部": "small general goods shop",
		"王宫": "royal palace complex",
		"宫殿": "palace interior and court symbols",
		"城墙": "city wall and gate defense",
		"铁匠": "blacksmith forge and anvils",
		"集市": "open market stalls",
		"奴隶": "servitude marks and social hierarchy",
		"庄园": "manor estate structure",
		"神殿": "temple architecture",
		"蒸汽": "steam machinery pipes and brass structure"
	}
	var anchors: Array = []
	for key in keyword_map.keys():
		if desc.find(str(key)) != -1:
			var anchor = str(keyword_map[key])
			if !anchors.has(anchor):
				anchors.append(anchor)
	return ", ".join(anchors)

static func build_location_fallback_description(location_name: String, from_site_name: String = "") -> String:
	var n = location_name.strip_edges()
	if n == "":
		return "你来到了一处新的地点。"
	if n.find("食堂") != -1:
		return "你来到" + n + "。热气和饭香交织，来往的人声让这里显得忙碌而真实。"
	if n.find("图书馆") != -1:
		return "你来到" + n + "。高书架与阅读区安静有序，空气里只有轻微翻页声。"
	if n.find("宿舍") != -1:
		return "你来到" + n + "。居住区的走廊延伸开来，生活痕迹随处可见。"
	if n.find("操场") != -1 or n.find("体育") != -1:
		return "你来到" + n + "。开阔场地上有人训练，风里带着土石与草木气息。"
	if n.find("教室") != -1 or n.find("教学楼") != -1:
		return "你来到" + n + "。讲学与讨论的痕迹还留在空气里，四周带着秩序感。"
	if n.find("超市") != -1 or n.find("小卖部") != -1:
		return "你来到" + n + "。铺面里货物陈列紧凑，交易声此起彼伏。"
	if from_site_name.strip_edges() != "":
		return "你来到" + n + "。这里与" + from_site_name + "相连，环境细节逐渐清晰起来。"
	return "你来到" + n + "。周围布局和气氛有了明显变化，这里看起来是可继续探索的区域。"

static func contains_any_keyword(text: String, words: Array) -> bool:
	var source = str(text)
	for w in words:
		if source.find(str(w)) != -1:
			return true
	return false

static func detect_setting_style_signals(world_seed_input: String, background: String) -> Dictionary:
	var t = (world_seed_input + " " + background).strip_edges()
	return {
		"ancient": contains_any_keyword(t, ["古代", "王朝", "朝廷", "封建", "奴隶制", "王国", "帝国", "城邦"]),
		"modern": contains_any_keyword(t, ["现代", "当代", "校园", "大学", "城市", "公司", "地铁", "工业化"]),
		"scifi": contains_any_keyword(t, ["科幻", "未来", "太空", "星际", "机甲", "机器人", "空间站"]),
		"cyber": contains_any_keyword(t, ["赛博", "义体", "霓虹", "黑客", "芯片植入"]),
		"fantasy": contains_any_keyword(t, ["魔法", "精灵", "神殿", "巫师", "异界", "巨龙"]),
		"slavery": contains_any_keyword(t, ["奴隶制", "奴隶主", "奴隶", "庄园主"]),
		"bridge": contains_any_keyword(t, ["穿越", "平行宇宙", "时空", "多元宇宙", "异世界桥接"])
	}

static func build_setting_consistency_guard_text(sig: Dictionary) -> String:
	var lines: Array = []
	if bool(sig.get("ancient", false)) and !bool(sig.get("bridge", false)):
		lines.append("ancient pre-industrial era only; forbid modern campus, cyberpunk neon, futuristic tech")
	if bool(sig.get("slavery", false)):
		lines.append("highlight hierarchical social structure and slave-based roles")
	if bool(sig.get("modern", false)) and !bool(sig.get("bridge", false)) and !bool(sig.get("scifi", false)):
		lines.append("modern realistic style; avoid ancient court language and sci-fi facilities")
	if bool(sig.get("scifi", false)) or bool(sig.get("cyber", false)):
		lines.append("futuristic sci-fi style allowed only when stated in world setting")
	if bool(sig.get("fantasy", false)) and !bool(sig.get("bridge", false)):
		lines.append("fantasy motif only; avoid modern institutional style")
	return "; ".join(lines)

static func build_scene_image_prompt(site_name: String, site_data: Dictionary, world_seed_input: String, background: String) -> String:
	var english_prompt = str(site_data.get("英文描述", "")).strip_edges()
	var cn_desc = str(site_data.get("地点描述", "")).strip_edges()
	var world_hint = background.strip_edges()
	var style_sig = detect_setting_style_signals(world_seed_input, background)
	var style_guard = build_setting_consistency_guard_text(style_sig)
	var location_hint = build_location_visual_hint(site_name, cn_desc)
	var desc_anchor = build_cn_desc_visual_anchor(cn_desc)
	var prompt_parts: Array = [
		"cinematic environment faithful to world setting",
		"daylight natural color",
		"no text, no watermark",
		"location:" + site_name
	]
	if style_guard != "":
		prompt_parts.append("style guard: " + style_guard)
	if world_hint != "":
		prompt_parts.append("world context: " + world_hint.left(120))
	if location_hint != "":
		prompt_parts.append(location_hint)
	if cn_desc != "":
		prompt_parts.append("narrative anchor: " + cn_desc.left(180))
	if desc_anchor != "":
		prompt_parts.append("must include visual elements: " + desc_anchor)
	if english_prompt != "":
		prompt_parts.append(english_prompt)
		if cn_desc != "":
			prompt_parts.append("if english prompt conflicts with narrative anchor, follow narrative anchor first")
	elif cn_desc != "":
		prompt_parts.append("scene detail: " + cn_desc.left(180))
	else:
		prompt_parts.append("scene detail: " + site_name)
	if site_data.has("npc") and site_data["npc"] is Dictionary:
		var npc_keys = (site_data["npc"] as Dictionary).keys()
		if !npc_keys.is_empty():
			if bool(style_sig.get("ancient", false)) and !bool(style_sig.get("bridge", false)):
				prompt_parts.append("people style: pre-modern attire and social hierarchy")
			elif bool(style_sig.get("scifi", false)) or bool(style_sig.get("cyber", false)):
				prompt_parts.append("people style: futuristic inhabitants consistent with lore")
			else:
				prompt_parts.append("people style: inhabitants fitting current world setting")
	if cn_desc != "":
		prompt_parts.append("keep architecture, facilities and props strictly aligned with narrative anchor")
	prompt_parts.append("strictly match this location and world era, avoid cross-era contamination")
	return ", ".join(prompt_parts)

static func build_npc_image_prompt(npc_name: String, npc_describe: String, world_seed_input: String, background: String) -> String:
	var style_sig = detect_setting_style_signals(world_seed_input, background)
	var parts: Array = [
		"anime character illustration",
		"character name: " + npc_name,
		"expressive eyes, detailed face, clean lineart, cel shading",
		"medium long shot, from thigh up, more body visible, subject scaled smaller in frame",
		"non-photorealistic, stylized 2d anime art",
		"simple clean background",
		"no text, no watermark"
	]
	if npc_describe.strip_edges() != "":
		parts.append("appearance: " + npc_describe.left(160))
	if bool(style_sig.get("ancient", false)) and !bool(style_sig.get("bridge", false)):
		parts.append("traditional historical attire, pre-modern style")
	elif bool(style_sig.get("scifi", false)) or bool(style_sig.get("cyber", false)):
		parts.append("futuristic sci-fi clothing")
	elif bool(style_sig.get("fantasy", false)):
		parts.append("fantasy medieval attire")
	else:
		parts.append("contemporary clothing fitting world setting")
	if background.strip_edges() != "":
		parts.append("world context: " + background.left(80))
	return ", ".join(parts)

static func build_bootstrap_scene_image_prompt(site_name: String, background: String) -> String:
	var n = str(site_name).strip_edges()
	if n == "":
		return ""
	var parts: Array = [
		"cinematic environment faithful to world setting",
		"daylight natural color",
		"no text, no watermark",
		"location:" + n
	]
	if background.strip_edges() != "":
		parts.append("world context: " + background.left(160))
	parts.append("scene detail: " + n)
	return ", ".join(parts)

static func build_explore_system_prompt(role_prompt: String, world_seed_input: String, background: String) -> String:
	var guards = "用户初始设定：" + world_seed_input + "\n"
	guards += "当前世界观：" + background + "\n"
	guards += "请确保地点、NPC、英文生图提示词与上述设定完全一致。"
	var style_sig = detect_setting_style_signals(world_seed_input, background)
	var style_guard = build_setting_consistency_guard_text(style_sig)
	if style_guard != "":
		guards += "\n设定一致性约束：" + style_guard
	guards += "\n硬性要求：输出JSON中的\u201c能前往的地点\u201d必须是3~6个可直达、互不重复、且不包含当前地点本身的地点名，不能为空。"
	return role_prompt + "\n" + guards
