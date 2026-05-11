extends RefCounted
class_name GameNpcPoolUtils

static func build_proactive_npc_pool(reason: String, style_sig: Dictionary) -> Array:
	var pool_map: Dictionary = {}
	if bool(style_sig.get("ancient", false)) and !bool(style_sig.get("bridge", false)):
		pool_map = {
			"money": [
				{"name": "集市掌柜", "describe": "拨着算盘、目光精明的掌柜"},
				{"name": "巡街差役", "describe": "腰挎短刀、神情警觉的差役"},
				{"name": "庄园管事", "describe": "衣着整肃、语气克制的管事"}
			],
			"exercise": [
				{"name": "武馆教头", "describe": "身形稳健、目光锐利的教头"},
				{"name": "营中老兵", "describe": "披着旧甲、说话干练的老兵"},
				{"name": "猎场向导", "describe": "背弓挎囊、步伐利落的向导"}
			],
			"time_pass": [
				{"name": "过路行商", "describe": "牵着驮兽、一路吆喝的行商"},
				{"name": "驿站信使", "describe": "披尘快步、神色匆匆的信使"},
				{"name": "城门小吏", "describe": "手持簿册、谨慎打量来人的小吏"}
			],
			"crime": [
				{"name": "巡城卫兵", "describe": "披甲执戟、面色不善的卫兵"},
				{"name": "庄园监工", "describe": "手持皮鞭、语气严厉的监工"},
				{"name": "目击商贩", "describe": "抱紧货箱、神色惊惧的商贩"}
			]
		}
	elif bool(style_sig.get("scifi", false)) or bool(style_sig.get("cyber", false)):
		pool_map = {
			"money": [
				{"name": "交易站文员", "describe": "佩戴终端、谨慎核验账目的文员"},
				{"name": "站区安保", "describe": "穿着防护装、目光冷静的安保"},
				{"name": "通道巡检员", "describe": "提着检测仪、步伐稳健的巡检员"}
			],
			"exercise": [
				{"name": "训练官", "describe": "佩戴护甲、下令简洁的训练官"},
				{"name": "机修技师", "describe": "手上沾着油污、动作麻利的技师"},
				{"name": "外勤队员", "describe": "背着装备包、目光冷静的队员"}
			],
			"time_pass": [
				{"name": "引导员", "describe": "手持投影地图、态度专业的引导员"},
				{"name": "远行乘客", "describe": "拖着箱包、神情疲惫的乘客"},
				{"name": "后勤调度员", "describe": "不断核对清单、语速很快的调度员"}
			],
			"crime": [
				{"name": "安保巡查员", "describe": "佩戴识别终端、语气冷硬的巡查员"},
				{"name": "目击维修工", "describe": "握着扳手、神情紧张的维修工"},
				{"name": "封控执行员", "describe": "启动警戒程序、要求你停下的执行员"}
			]
		}
	else:
		pool_map = {
			"money": [
				{"name": "路过行人", "describe": "步伐匆匆、却忍不住多看你一眼的行人"},
				{"name": "值守人员", "describe": "神情警觉、习惯观察周围的值守人员"},
				{"name": "小摊商贩", "describe": "守着摊位、眼神精明的商贩"}
			],
			"exercise": [
				{"name": "训练者", "describe": "动作利落、状态很好的训练者"},
				{"name": "晨练路人", "describe": "呼吸平稳、步伐轻快的路人"},
				{"name": "教习", "describe": "目光专注、语气沉稳的教习"}
			],
			"time_pass": [
				{"name": "热心路人", "describe": "愿意搭话、对周围很熟悉的路人"},
				{"name": "陌生访客", "describe": "拿着地图、看起来有些迷路的人"},
				{"name": "本地向导", "describe": "语气友好、对地形很熟的向导"}
			],
			"crime": [
				{"name": "巡逻人员", "describe": "脚步急促、神情严肃地靠近你的人"},
				{"name": "目击者", "describe": "突然出现在旁边、一脸惊讶的目击者"},
				{"name": "工作人员", "describe": "眼神警惕、快步走来的工作人员"}
			]
		}
	if pool_map.has(reason):
		return pool_map[reason]
	return []

static func pick_crime_npc_fallback(site_name: String, style_sig: Dictionary) -> Dictionary:
	if site_name.find("宿舍") != -1:
		return {"name": "宿管阿姨", "describe": "拿着登记本、神情警惕地走了过来"}
	if site_name.find("学校") != -1 or site_name.find("教学") != -1:
		return {"name": "值班老师", "describe": "皱着眉、快步走来的值班老师"}
	if bool(style_sig.get("ancient", false)) and !bool(style_sig.get("bridge", false)):
		return {"name": "巡城卫兵", "describe": "披甲执戟、神情严厉地拦下了你"}
	if bool(style_sig.get("scifi", false)) or bool(style_sig.get("cyber", false)):
		return {"name": "安保巡查员", "describe": "佩戴识别终端、语气冷硬地要求你停下"}
	return {}
