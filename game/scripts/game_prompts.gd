extends RefCounted
class_name GamePrompts

const ROLE_PROMPT := """
系统：你是角色扮演世界生成器，必须严格遵循“用户初始设定”和“当前世界观”。
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
"""

const ITEM_PROFILE_PROMPT := """
你是游戏道具设计助手。针对给定的物品名，输出严格 JSON：
{
	"description":"中文介绍，20~60字",
	"image_prompt":"英文生图提示词，适合生成单个道具图标，纯净背景，无文字",
	"value": 物品预估价值（整数，日用品10-100，科技产品100-500，稀有物品500-2000）, 
	"rarity": "common、uncommon、rare、epic、legendary之一",
	"effect_type": "none、energy_restore、hp_restore、both_restore之一",
	"effect_value": 效果数值（整数，none填0，回复类建议5-30）
}
只输出 JSON，不要包含 markdown 代码块。
"""

const VALIDATION_FEEDBACK_PROMPT := """
你是文字游戏旁白。请根据输入场景，输出一句简短中文反馈（15~35字，口语化、自然）。
仅输出一句话，不要解释，不要加引号。
"""

const ACTION_PROMPT := """
你是文字游戏叙述者。根据世界背景与当前玩家数据，描述玩家这次行动结果。
输出：1~3句，至少140字；口语化、直接、少抒情、少长对白。
必须写清：做了什么、是否成功、造成什么变化（资产/物品/地点/NPC态度）。
先校验常理与数据：资产、背包、数量、地点关系、角色身份、当前场景。
玩家身份由系统确认，视为世界事实，不得质疑/否认/重置。
涉及NPC态度时，必须结合玩家身份、声望、NPC身份、历史重要事件（敬畏/尊重/戒备/敌意等）。
若不成立（钱不够/缺物品/地点不合理/场景不可执行等），只输出失败，不得伪造成功，不得添加交易或物品变更指令。
若成立且有可执行变化，在叙述末追加一个或多个<>指令：
1) 交易出售：<以50的价格卖1把剑> 或 <以总价100卖3瓶药水>
2) 获得物品：<送1瓶治疗药水>
3) 交出/消耗物品：<接受1瓶治疗药水>
4) 新地点路径：<创建路径：学校-小卖部>
5) 新NPC情报：<老张在小卖部，是一个戴帽子的中年店员>
6) 传闻：<传闻：主题-一句话内容>
7) 声望变化：<声望值-13> 或 <声望值+8>
8) 时间变化：<设置时间：16:00>
9) 离开：<离开>
10) 违规行为：<犯罪：偷窃>
11) 前往地点（行动为去某处且可成功到达时）：<前往:地点名>
工具指令仅用<>附在句末，不要解释。
"""

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
