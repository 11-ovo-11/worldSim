extends RefCounted
class_name GameEventUtils

static func is_important_log(log_text: String) -> bool:
	var t = str(log_text).strip_edges()
	if t == "":
		return false
	if t.find("<BG_DEBUG>") != -1:
		return false
	var keywords = [
		"【行动】", "你抵达了", "地图更新", "传闻", "声望", "时间", "购买", "失去", "获得",
		"违规", "防盗", "警报", "主动", "交谈", "读档", "保存", "交易", "送你"
	]
	for k in keywords:
		if t.find(k) != -1:
			return true
	return false

static func extract_npc_result_outcome_flags(plain_text: String, sig: Dictionary) -> Dictionary:
	var source = str(plain_text).strip_edges()
	var accepted = GameEntityUtils.contains_keyword(source, ["接受", "收下", "接过", "答应", "同意", "愿意", "允许", "放行", "成交", "买下", "卖给", "告诉你", "带你", "让你", "配合", "照办", "原谅", "饶过"])
	var rejected = GameEntityUtils.contains_keyword(source, ["拒绝", "回绝", "谢绝", "不肯", "不愿", "不同意", "无视", "不理", "赶走", "驱逐", "轰走", "拦住", "阻止", "阻拦"])
	var cooperated = int(sig.get("assist", 0)) > 0 or GameEntityUtils.contains_keyword(source, ["帮你", "协助", "接应", "带路", "照应", "掩护", "治疗", "救下", "保护", "替你", "配合"])
	var traded = int(sig.get("trade", 0)) > 0 or GameEntityUtils.contains_keyword(source, ["交易", "成交", "买下", "卖给", "付款", "付钱", "报价", "按价", "钱货两清"])
	var gifted = int(sig.get("gift", 0)) > 0 or GameEntityUtils.contains_keyword(source, ["送", "赠", "递给", "交给", "给你", "给我", "补给", "分享"])
	var warned = GameEntityUtils.contains_keyword(source, ["警报", "报警", "通缉", "围住", "盘问", "搜身", "扣留", "盯上", "怀疑", "戒备", "防盗", "违规"])
	var harmed = GameEntityUtils.contains_keyword(source, ["威胁", "命令", "逼", "强迫", "羞辱", "冒犯", "欺骗", "骗", "偷", "抢", "打伤", "伤害", "砍", "捅", "勒索", "辱骂"])
	var breached = GameEntityUtils.contains_keyword(source, ["食言", "失约", "赖账", "反悔", "违约", "不守信用", "说话不算"])
	var protected = GameEntityUtils.contains_keyword(source, ["救", "保护", "掩护", "照顾", "安慰", "治疗", "扶住", "拉开", "挡下"])
	var softened = GameEntityUtils.contains_keyword(source, ["感谢", "谢谢", "道歉", "赔偿", "归还", "谅解", "缓和", "客气"])
	if warned:
		rejected = true
	if int(sig.get("coercion", 0)) > 0:
		harmed = true
	if traded and GameEntityUtils.contains_keyword(source, ["成交", "买下", "卖给", "付款", "钱货两清"]):
		accepted = true
	if gifted and GameEntityUtils.contains_keyword(source, ["接受", "收下", "接过"]):
		accepted = true
	if protected:
		cooperated = true
	return {
		"accepted": accepted,
		"rejected": rejected,
		"cooperated": cooperated,
		"traded": traded,
		"gifted": gifted,
		"warned": warned,
		"harmed": harmed,
		"breached": breached,
		"protected": protected,
		"softened": softened
	}

static func should_store_npc_personal_event(plain_text: String, sig: Dictionary) -> bool:
	var t = str(plain_text).strip_edges()
	if t == "":
		return false
	if t.begins_with("【行动】"):
		return false
	var outcome_flags = extract_npc_result_outcome_flags(t, sig)
	if bool(outcome_flags.get("accepted", false)) or bool(outcome_flags.get("rejected", false)) or bool(outcome_flags.get("cooperated", false)):
		return true
	if bool(outcome_flags.get("warned", false)) or bool(outcome_flags.get("harmed", false)) or bool(outcome_flags.get("breached", false)):
		return true
	if bool(outcome_flags.get("gifted", false)) or bool(outcome_flags.get("traded", false)) or bool(outcome_flags.get("protected", false)):
		return true
	if bool(outcome_flags.get("softened", false)):
		return true
	if int(sig.get("trade", 0)) > 0 or int(sig.get("gift", 0)) > 0 or int(sig.get("assist", 0)) > 0:
		return true
	if int(sig.get("positive", 0)) > 0 or int(sig.get("negative", 0)) > 0 or int(sig.get("coercion", 0)) > 0 or int(sig.get("respect", 0)) > 0:
		return true
	var keep_keywords = [
		"传闻", "声望", "违规", "警报", "离开", "拒绝", "同意", "成交", "感谢", "敌意", "戒备", "尊重", "敬畏", "帮", "救", "冲突", "道歉", "威胁", "命令", "羞辱", "冒犯", "安慰", "保护", "信任", "怀疑", "欺骗", "冷淡", "亲近"
	]
	for kw in keep_keywords:
		if t.find(kw) != -1:
			return true
	return false

# plain_text: pre-processed (angle tags stripped)
static func build_npc_perspective_event_text(plain_text: String, npc_name: String, focus_npc: String) -> String:
	var t = plain_text.strip_edges()
	if t == "":
		return ""
	if npc_name == focus_npc:
		if t.begins_with("传闻："):
			return "我听到一条传闻：" + t.trim_prefix("传闻：").strip_edges()
		return "我亲历了：" + t
	if t.begins_with("传闻："):
		return "和我有关的一条传闻：" + t.trim_prefix("传闻：").strip_edges()
	return "和我相关的重要事件：" + t

static func build_npc_personal_event_summary(plain_text: String, npc_name: String, focus_npc: String, sig: Dictionary) -> String:
	var t = str(plain_text).strip_edges()
	if !should_store_npc_personal_event(t, sig):
		return ""
	var _outcome_flags = extract_npc_result_outcome_flags(t, sig)
	if t.begins_with("传闻："):
		var rumor_text = t.trim_prefix("传闻：").strip_edges()
		if npc_name == focus_npc:
			return "我获知传闻：" + rumor_text
		return "相关传闻：" + rumor_text
	if npc_name == focus_npc:
		return "我记住了一件会直接影响我对玩家态度的事：" + t
	return "有一件与我相关的事会影响我之后对玩家的判断：" + t

static func score_event_relevance(mem: Dictionary, site_name: String, npc_name: String, intent_hint: Dictionary = {}) -> int:
	var score = 0
	if str(mem.get("site", "")) == site_name and site_name != "":
		score += 2
	if npc_name != "":
		var arr = mem.get("npcs", [])
		if arr is Array and arr.has(npc_name):
			score += 4
	if !intent_hint.is_empty():
		score += min(int(mem.get("trade", 0)), int(intent_hint.get("trade", 0)))
		score += min(int(mem.get("gift", 0)), int(intent_hint.get("gift", 0)))
		score += min(int(mem.get("assist", 0)), int(intent_hint.get("assist", 0)))
	return score
