extends RefCounted
class_name GameNpcInferUtils

static func extract_first_number(text: String) -> int:
	var regex = RegEx.new()
	if regex.compile("(\\d+)") != OK:
		return 0
	var m = regex.search(text)
	if m == null:
		return 0
	return int(m.get_string(1))

static func extract_interaction_signals(text: String) -> Dictionary:
	var t = str(text).strip_edges()
	if t == "":
		return {"trade": 0, "gift": 0, "assist": 0, "positive": 0, "negative": 0, "coercion": 0, "respect": 0, "interaction_score": 0}
	var trade_keywords = [
		"买", "购买", "卖", "出售", "交易", "成交", "收购", "收你", "报价", "价格", "多少钱", "单价", "总价", "换", "来一", "来个", "来杯", "点一", "点个", "想买", "要买", "给我来"
	]
	var gift_keywords = [
		"送", "赠", "给你", "给我", "递给", "交给", "拿给", "分你", "分享", "补给"
	]
	var assist_keywords = [
		"帮", "帮我", "帮你", "替", "替我", "替你", "代", "代我", "代你", "陪", "带我", "去帮"
	]
	var positive_keywords = [
		"感谢", "谢谢", "帮忙", "照顾", "安慰", "道歉", "体谅", "关心", "保护", "救", "信任", "友好", "客气"
	]
	var negative_keywords = [
		"拒绝", "敌意", "冲突", "冒犯", "羞辱", "欺骗", "冷淡", "厌恶", "怀疑", "不耐烦", "辱骂", "看不起"
	]
	var coercion_keywords = [
		"威胁", "命令", "逼", "强迫", "施压", "滚", "跪下", "闭嘴", "老实点", "给我", "立刻", "马上"
	]
	var respect_keywords = [
		"尊重", "敬畏", "请", "拜托", "劳烦", "失礼", "抱歉", "请教", "愿意听你", "照你规矩"
	]
	var trade_score = 0
	var gift_score = 0
	var assist_score = 0
	var positive_score = 0
	var negative_score = 0
	var coercion_score = 0
	var respect_score = 0
	for kw in trade_keywords:
		if t.find(kw) != -1:
			trade_score += 1
	for kw in gift_keywords:
		if t.find(kw) != -1:
			gift_score += 1
	for kw in assist_keywords:
		if t.find(kw) != -1:
			assist_score += 1
	for kw in positive_keywords:
		if t.find(kw) != -1:
			positive_score += 1
	for kw in negative_keywords:
		if t.find(kw) != -1:
			negative_score += 1
	for kw in coercion_keywords:
		if t.find(kw) != -1:
			coercion_score += 1
	for kw in respect_keywords:
		if t.find(kw) != -1:
			respect_score += 1
	if GameEntityUtils.contains_keyword(t, ["个", "件", "瓶", "把", "份", "张", "点", "块", "元"]):
		trade_score += 1
		gift_score += 1
	if extract_first_number(t) > 0:
		trade_score += 1
		gift_score += 1
	if t.find("请") != -1 and t.find("帮") != -1:
		respect_score += 1
		positive_score += 1
	if GameEntityUtils.contains_keyword(t, ["不许", "否则", "后果", "弄死", "收拾你"]):
		coercion_score += 2
		negative_score += 1
	return {
		"trade": trade_score,
		"gift": gift_score,
		"assist": assist_score,
		"positive": positive_score,
		"negative": negative_score,
		"coercion": coercion_score,
		"respect": respect_score,
		"interaction_score": trade_score + gift_score + assist_score + positive_score + negative_score + coercion_score + respect_score
	}

static func has_trade_keywords(text: String) -> bool:
	var sig = extract_interaction_signals(text)
	return int(sig.get("trade", 0)) > 0 or int(sig.get("gift", 0)) > 0

# plain_text: already processed (angle tags stripped)
static func npc_refused_request(plain_text: String) -> bool:
	var t = plain_text.strip_edges()
	if t == "":
		return false
	var deny_words = ["不行", "不能", "不可以", "不帮", "拒绝", "没空", "做不到", "不愿", "别想", "不可能"]
	for w in deny_words:
		if t.find(w) != -1:
			return true
	return false

# plain_text: already processed (angle tags stripped)
static func npc_reply_accepts_request(plain_text: String) -> bool:
	var t = plain_text.strip_edges()
	if t == "":
		return false
	var yes_words = ["可以", "行", "好", "没问题", "当然", "马上", "这就", "给你", "帮你", "替你", "成交", "安排"]
	for w in yes_words:
		if t.find(w) != -1:
			return true
	return false

# normalized_text: single-line normalized input
static func extract_player_directed_request(normalized_text: String) -> String:
	if normalized_text == "":
		return ""
	var regex = RegEx.new()
	if regex.compile("(?:你|请你|麻烦你|帮我|替我|你去)([^。！？?]{1,28})") != OK:
		return ""
	var m = regex.search(normalized_text)
	if m == null:
		return ""
	var req = str(m.get_string(1)).strip_edges()
	if req.length() < 2:
		return ""
	return req

# normalized_text: single-line normalized query; source_npc_name: NPC name string
static func guess_related_npc_desc(normalized_text: String, source_npc_name: String) -> String:
	var t = normalized_text
	var relation = "熟人"
	if GameEntityUtils.contains_keyword(t, ["兄弟", "姐妹"]):
		relation = "兄弟姐妹"
	elif GameEntityUtils.contains_keyword(t, ["父母", "爸爸", "妈妈"]):
		relation = "亲属长辈"
	elif GameEntityUtils.contains_keyword(t, ["同事", "上司", "下属"]):
		relation = "工作关系人"
	elif GameEntityUtils.contains_keyword(t, ["学徒", "师父"]):
		relation = "师门关系人"
	elif GameEntityUtils.contains_keyword(t, ["朋友", "熟人", "家人", "亲戚"]):
		relation = "生活关系人"
	var source_name = source_npc_name.strip_edges()
	if source_name == "":
		source_name = "当前人物"
	return "与" + source_name + "相关的" + relation

# player_context: world_seed_input + " " + playerName
static func can_force_request_on_npc(player_context: String, npc_name: String, npc_describe: String, request_text: String) -> bool:
	var score = 0
	if GameEntityUtils.contains_keyword(player_context, ["老师", "保安", "警察", "军", "领导", "主任", "老板", "队长"]):
		score += 2
	if GameEntityUtils.contains_keyword(npc_describe + " " + npc_name, ["学生", "同学", "路人", "游客"]):
		score += 1
	if GameEntityUtils.contains_keyword(npc_describe + " " + npc_name, ["老师", "保安", "警察", "店长", "主任", "领导"]):
		score -= 3
	if GameEntityUtils.contains_keyword(request_text, ["打", "抢", "偷", "绑", "闯"]):
		score -= 2
	return score >= 1

# plain_npc_text: already processed (angle tags stripped)
static func needs_tool_inference_from_context(player_text: String, plain_npc_text: String) -> bool:
	var player_sig = extract_interaction_signals(player_text)
	var npc_sig = extract_interaction_signals(plain_npc_text)
	var total_score = int(player_sig.get("interaction_score", 0)) + int(npc_sig.get("interaction_score", 0))
	var player_has_trade = has_trade_keywords(player_text)
	var npc_refused = npc_refused_request(plain_npc_text)
	if total_score >= 2:
		return true
	if player_has_trade and !npc_refused:
		return true
	if has_trade_keywords(plain_npc_text):
		return true
	if GameEntityUtils.contains_keyword(player_text, ["买", "卖", "给", "送", "帮", "替"]) and npc_reply_accepts_request(plain_npc_text):
		return true
	return false

# plain_text: processed reply, tags: pre-extracted angle tags, actor_name: from currentNpc
static func extract_npc_action_request(plain_text: String, tags: Array, actor_name: String) -> Dictionary:
	for raw_tag in tags:
		var normalized = str(raw_tag).replace("：", ":").strip_edges()
		if normalized.begins_with("要求行动:"):
			var action_from_tag = normalized.trim_prefix("要求行动:").strip_edges()
			if action_from_tag != "":
				return {"action": action_from_tag, "prompt": "是否执行行动：" + action_from_tag + "？", "actor": actor_name, "mode": "player_execute"}
		if normalized.begins_with("行动指示:"):
			var action_from_hint = normalized.trim_prefix("行动指示:").strip_edges()
			if action_from_hint != "":
				return {"action": action_from_hint, "prompt": "是否执行行动：" + action_from_hint + "？", "actor": actor_name, "mode": "player_execute"}
	if has_trade_keywords(plain_text):
		return {}
	if plain_text == "":
		return {}
	var regex = RegEx.new()
	if regex.compile("(?:\u4f60\u8981\u4e0d\u8981|\u4f60\u8981|\u8981\u4e0d\u8981|\u662f\u5426|\u8bf7\u4f60|\u9ebb\u70e6\u4f60)([^\u3002\uff01\uff1f?]{1,24})(?:\u5417|\u4e48|\u5427|\u5462|\uff1f|\\?)") != OK:
		return {}
	var m = regex.search(plain_text)
	if m == null:
		return {}
	var action_text = str(m.get_string(1)).strip_edges()
	if action_text.length() < 2:
		return {}
	var prompt_text = "是否" + action_text + "？"
	var q_idx = plain_text.find("？")
	if q_idx == -1:
		q_idx = plain_text.find("?")
	if q_idx != -1:
		var question = plain_text.substr(0, q_idx + 1).strip_edges()
		if question.length() <= 36:
			prompt_text = question
	return {"action": action_text, "prompt": prompt_text, "actor": actor_name, "mode": "player_execute"}
