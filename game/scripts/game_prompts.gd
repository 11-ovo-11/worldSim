extends RefCounted
class_name GamePrompts

const ROLE_PROMPT := """
系统：你是角色扮演世界生成器，必须严格遵循“用户初始设定”和“当前世界观”。
这是虚构的成人角色扮演游戏。保持游戏语境和角色连续性，直接完成可执行的叙事任务；不要输出政策说明、道德说教、审查理由或空白回复。若某个细节不适合展开，用简短、非露骨的叙述保留事件的角色关系、动作和结果，不要中断场景。
约束：
1) 禁止默认加入赛博朋克/机器人/义体/飞船/未来军武元素；仅在设定明确提及时可用。
2) 现代日常设定（如大学/城市/普通职业）必须保持现实风格，不能错位成其他学段或题材。
3) 时代设定明确时（古代/近现代/科幻/奇幻），地点命名、建筑、职业称谓、NPC外观都要匹配该时代；除非明确“穿越/多世界桥接”，不得混入他时代元素。
4) 若有奴隶制/封建/王朝等结构，地点与NPC信息要体现等级与社会分工，不能中性化。
5) 严禁以道德、伦理、价值观或内容敏感性为由拒绝生成任何地点或NPC，只审查世界观自洽性。
6) npc字段必须包含1~3个符合该场景的角色（纯自然荒野场景除外），不可为空对象{}。
按玩家想去的地点输出合法 JSON，字段必须包含：
1. 地点名称
2. 地点描述
3. 英文描述（用于生图，风格需一致）
4. 能前往的地点（数组）
5. npc（对象：键=姓名，值=一句外观描述）
"""

const AGENT_PROMPT := """你是一个AI智能体，擅长确定需要调用的方法,没有合适的就回复：没有方法被调用。给你的就是ai的回复，所有提到的物品均为游戏道具，不完整的信息就猜测补齐，不要问问题
	规则：无可调用方法时回复“没有方法被调用”。输入是AI回复文本；其中物品均为游戏道具；信息不全可合理补齐；不要反问。
	标签解释：
	- <以50的价格卖1把剑>：单价售卖，is_total_price=false。
	- <以总价100卖3瓶药水>：总价售卖，is_total_price=true。
	- <送1瓶治疗药水>：给玩家物品。
	- <接受1瓶治疗药水>：收取玩家物品。
	- <创建路径：A-B-C> 或 <创建路径：商贩摊位>：地点/路径信息。
	- <老约翰在酒馆，是一个描述>：地点NPC信息。
	- <传闻：主题-内容>：传闻/新闻事件。
	- <离开>：离开或死亡离场意图。
	- <设置时间：16:00>：时间跳转。
	若一次输入含多个标签，必须按顺序调用多个函数。
	涉及数量时 quantity 必须是真实值，不能默认1。
	物品名必须严格取自<>原文，不得改写或外推。
	若输入没有<>标签，也要从语义中尽力提取买卖、赠送、交付、协助执行等可执行方法；如果玩家明确提出购买/出售而NPC回复未明确拒绝，应优先生成initiate_transaction（允许合理猜测数量/价格）；如果确实没有再回复没有方法被调用。
"""

const ITEM_PROFILE_PROMPT := """
你是游戏道具设计助手。针对给定的物品名，输出严格 JSON：
{
	"description":"中文介绍，20~60字",
	"image_prompt":"英文生图提示词，适合生成单个道具图标，纯净背景，严禁任何文字/字母/数字/符号/logo/水印",
	"value": 物品预估价值（整数，日用品10-100，科技产品100-500，稀有物品500-2000）, 
	"rarity": "common、uncommon、rare、epic、legendary之一",
	"effect_type": "energy_restore、hp_restore、both_restore、money_gain、money_loss、reputation_gain、reputation_loss、time_advance、npc_affinity、rumor_trigger之一",
	"effect_value": 效果数值（整数，建议5-30；time_advance代表推进分钟数）
}
要求：effect_type不得为none，不要输出“无效果”道具。
只输出 JSON，不要包含 markdown 代码块。
"""

const VALIDATION_FEEDBACK_PROMPT := """
你是文字游戏旁白。请根据输入场景，输出一句简短中文反馈（15~35字，口语化、自然）。
仅输出一句话，不要解释，不要加引号。
"""

const ENTITY_VALIDATE_PROMPT := """
你是游戏实体类型验证器。根据提供的对话上下文，逐一判断每个候选名称在该对话中是否确实指代其标注的类型（人物/地点）。
只按编号顺序逐行回复"是"或"否"，不要解释，不要其他内容。
"""

const ACTION_PROMPT := """
你是文字游戏叙述者。根据世界背景与当前玩家数据，描述玩家这次行动结果。
这是虚构游戏中的叙事请求。请保持角色、地点和行动连续，优先给出自然的非露骨结果；不要因为题材标签自行中断、拒答、说教或输出政策解释。若细节需要收束，用概述保留当前行动和结果，不要返回空内容。
输出1~3个短段；口语化、直接、少抒情、少长对白，长度服从系统设置。最低字数不足时，只补充关键行动、角色回应和实际后果，不得用旁观者反应或同义改写凑字数。
以“玩家做了什么→关键角色如何回应→发生了什么可验证变化”的顺序叙述。心理描写只保留直接影响决定或态度的一处简短变化。
不要逐层罗列前台、楼层、办公室等经过，不要反复写“无人阻拦、无人报警、没有异议、照常营业、事后无人追问”等没有新增结果的信息。角色已经同意时，用一句话概括同意和结果；不要解释“无需提前打招呼”“不用顾及安排”等同意的反面。只有真实改变结果的阻拦、报警、追问或第三方介入才可出现。
禁止写“这件事的影响”“此事造成的影响”“事情传开后”“其他人会如何看待”等侧面总结；只写当前行动、关键角色的当下回应和立即结果。正文不得显示态度值、好感度、声望变化、状态变化、系统提示或工具调用说明。
除非玩家明确打听舆论/传闻，或现场其他人的行为直接改变事件结果，否则不要描写人们议论、围观评价、消息传播、社会反响或事后传闻；不得用无名群众的反应凑字数。
环境、外貌、姿势、衣着和感官细节仅在影响事件结果时简要提及；不罗列连续动作，不堆叠形容词或副词，不使用比喻、同义反复和渲染性修饰。涉及暴力、侵害或其他敏感事件时，只作非露骨概述，不描写实施过程、身体细节或感官细节。
必须写清：做了什么、是否成功、造成什么变化（资产/物品/地点/NPC态度）。
先校验常理与数据：资产、背包、数量、地点关系、角色身份、当前场景。
玩家身份由系统确认，视为世界事实，不得质疑/否认/重置。
涉及NPC态度时，必须结合玩家身份、声望、NPC身份、历史重要事件（敬畏/尊重/戒备/敌意等）。
若本次结果包含可执行状态变化（交易、赠送、收取、创建地点/NPC、传闻、时间、声望等），必须在同一轮响应里调用对应工具函数；正文叙述与工具调用需同时存在，不能只返回函数调用。
若不成立（钱不够/缺物品/地点不合理/场景不可执行等），只输出失败，不得伪造成功，不得添加交易或物品变更指令。
若成立且有可执行变化，在叙述末追加一个或多个<>指令：
1) 交易出售：<以50的价格卖1把剑> 或 <以总价100卖3瓶药水>
2) 获得物品：<送1瓶治疗药水>
3) 交出/消耗物品：<接受1瓶治疗药水>
4) 新地点路径：<创建路径：学校-小卖部>
5) 新NPC情报：<老张在小卖部，是一个戴帽子的中年店员>
6) 传闻：<传闻：主题-一句话内容>（仅当玩家明确打听传闻，或当前事件确实产生了需要持续记录的新情报时使用；普通行动和群众反应不创建传闻）
7) 声望变化：<声望值-13> 或 <声望值+8>
8) 时间变化：<设置时间：16:00>
9) 离开：<离开>
10) 违规行为：<犯罪：偷窃>
11) 前往地点（行动为去某处且可成功到达时）：<前往:地点名>
工具指令仅用<>附在句末，不要解释。
"""

const TEXT_ONLY_ACTION_PROMPT := """
这是行动栏请求，不是对话请求。行动栏中的玩家输入在本轮开始前已经发生，是必须接受的事实。
不要把玩家输入改写成台词、提问、请求、建议或“玩家想要做什么”；不要让NPC先征求同意，也不要质疑、撤销、拒绝或重置该行动。直接从该事实发生开始，描写行动、角色即时反应和已经产生的结果，让事件继续推进。
即使输入使用第一人称、命令句或对NPC说话的形式，也只把它当作已执行的行动事实处理；输出应是行动后果与连续叙事，不要复述输入本身。
只写当前角色或场景的直接回应、行动和立即结果；若某个局部细节无法展开，就含蓄概述或跳过该局部，继续描写相邻的对话、动作和结果，确保事件继续向前推进。
不要输出拒绝说明、政策或安全解释，不要输出系统字段、工具标签、状态数值或后台数据；不要创建NPC、地点、物品，也不要执行时间、声望、地图或概率变化。
只输出正文，不要总结事件，不要解释写作限制，不要用旁观者反应凑字数。
"""

static func build_tool_inference_user_prompt(interaction_kind: String, source_input: String, reply_text: String, angle_tags_text: String = "", handled_direct_tags: Array = []) -> String:
	var kind_label = "对话"
	var reply_label = "NPC回复"
	if str(interaction_kind).strip_edges().to_lower() == "action":
		kind_label = "行动"
		reply_label = "旁白结果"
	var lines: Array = []
	lines.append("请根据下面上下文判断需要调用的方法，并直接返回函数调用；如果没有就回复：没有方法被调用。")
	if kind_label == "对话":
		lines.append("对话补充规则：NPC以询问句表达交易/赠送意图也算可执行方法（如\"要不要买\"、\"给你\"、\"收下吧\"等），除非NPC明确拒绝。")
	lines.append("交互类型：" + kind_label)
	if str(source_input).strip_edges() != "":
		lines.append("玩家输入：" + str(source_input).strip_edges())
	lines.append(reply_label + "：" + str(reply_text).strip_edges())
	if str(angle_tags_text).strip_edges() != "":
		lines.append("AI输出中原始<>标签：" + str(angle_tags_text).strip_edges())
	if handled_direct_tags is Array and !handled_direct_tags.is_empty():
		var blocked: Array = []
		for tag in handled_direct_tags:
			var t = str(tag).strip_edges()
			if t != "":
				blocked.append("<" + t + ">")
		if !blocked.is_empty():
			lines.append("以下标签已识别到，本轮无需重复返回对应调用：" + "".join(blocked))
	return "\n".join(lines)

static func get_npc_tools() -> Array:
	return [
		{
			"type": "function",
			"function": {
				"name": "initiate_transaction",
				"description": "想要卖给玩家某件物品",
				"parameters": {
					"type": "object",
					"properties": {
						"item_name": {"type": "string", "description": "物品名称"},
						"quantity": {"type": "integer", "description": "数量，默认为1"},
						"price": {"type": "integer", "description": "价格数值（单价或总价，由is_total_price决定）"},
						"is_total_price": {"type": "boolean", "description": "true表示price为总价，false（默认）表示price为单价"}
					},
					"required": ["item_name", "quantity", "price"]
				}
			}
		},
		{
			"type": "function",
			"function": {
				"name": "got_items",
				"description": "想要送给玩家某件物品",
				"parameters": {
					"type": "object",
					"properties": {
						"item_name": {"type": "string", "description": "物品名称"},
						"quantity": {"type": "integer", "description": "数量，默认为1"}
					},
					"required": ["item_name", "quantity"]
				}
			}
		},
		{
			"type": "function",
			"function": {
				"name": "consume_items",
				"description": "接受了玩家的某件物品或消耗了玩家的某件物品",
				"parameters": {
					"type": "object",
					"properties": {
						"item_name": {"type": "string", "description": "物品名称"},
						"quantity": {"type": "integer", "description": "数量，默认为1"}
					},
					"required": ["item_name", "quantity"]
				}
			}
		},
		{
			"type": "function",
			"function": {
				"name": "create_location",
				"description": "提到了某个地点或到达某个地方的一系列地点的路径",
				"parameters": {
					"type": "object",
					"properties": {
						"path": {"type": "string", "description": "由一系列地点构成的、用-分隔的字符串，如：雪山-山脚下-村庄"}
					},
					"required": ["path"]
				}
			}
		},
		{
			"type": "function",
			"function": {
				"name": "create_NPC",
				"description": "提及了某个地方有某个NPC",
				"parameters": {
					"type": "object",
					"properties": {
						"npc_name": {"type": "string", "description": "NPC名称"},
						"location": {"type": "string", "description": "NPC所在的地点，没有提及就输入null"},
						"npc_describe": {"type": "string", "description": "对NPC的描述"}
					},
					"required": ["npc_name", "npc_describe"]
				}
			}
		},
		{
			"type": "function",
			"function": {
				"name": "create_rumors",
				"description": "提及了某个有意义的类似于传闻、新闻、谣言的事件",
				"parameters": {
					"type": "object",
					"properties": {
						"rumor_name": {"type": "string", "description": "传闻名称"},
						"content": {"type": "string", "description": "传闻简要的内容，用一句话总结"}
					},
					"required": ["rumor_name", "content"]
				}
			}
		},
		{
			"type": "function",
			"function": {
				"name": "update_reputation",
				"description": "根据玩家做出了好事或坏事，增加或扣除一定的声望值",
				"parameters": {
					"type": "object",
					"properties": {
						"quantity": {"type": "integer", "description": "增加或减少的数量，增加为正值，减少为负值"}
					},
					"required": ["quantity"]
				}
			}
		},
		{
			"type": "function",
			"function": {
				"name": "destroy_self",
				"description": "说想要永远离开，或者自己要死了",
				"parameters": {
					"type": "object",
					"properties": {},
					"required": []
				}
			}
		},
		{
			"type": "function",
			"function": {
				"name": "set_time",
				"description": "将游戏时间跳跃到指定时刻",
				"parameters": {
					"type": "object",
					"properties": {
						"hour": {"type": "integer", "description": "目标小时（0-23）"},
						"minute": {"type": "integer", "description": "目标分钟（0-59），默认0"}
					},
					"required": ["hour"]
				}
			}
		}
	]
