# 即时场景背景

在对话区的“设置”中开启“即时生成场景背景”并确认，开关会成为之后运行的默认值。
开启后，每次有效的 NPC 回复或行动回复都会异步生成环境背景；切换开关不会改变文本提示词和记忆逻辑。
关闭后停止新的图片请求并保留最后一张背景。

## Codex 命令行（默认）

默认通道为 `WORLD_SIM_BACKGROUND_PROVIDER=codex_cli`，不要求另配 `OPENAI_API_KEY`。
本机已实测 Codex CLI 0.154.0 的内置 `image_gen.imagegen` 可以生成图片。
游戏把短场景资料交给独立的 `codex exec` 任务，读取生成的 PNG 后替换背景；不会向当前桌面聊天注入消息。
命令行需安装、登录并具有内置生图权限；使用限制及计费取决于 Codex 的实际登录/账户配置，不能视为无限免费。

```powershell
codex --version
codex login
codex features list
```

`GET /instant_image_status` 仅检查本机是否找到 CLI，不会主动生成图片，也不代表账户权限或额度验证成功。
命令行任务位于独立临时目录，使用 `workspace-write` 沙箱，场景文本通过标准输入发送，不拼接成 shell 命令。
任务不得读取原始存档、项目配置或密钥；不允许在内置工具不可用时静默改用付费图片 API。

### 人物立绘绑定

- 当前对话 NPC 优先，再查找本轮叙事中明确提到的已有人物；最多附带三张立绘。
- 从原始缓存/本地 NPC 图片中读取图像，通过 CLI `--image` 作为实际图片输入，并附带人物名与图片对应表。
- 要求内置生图工具继续使用这些图像参考，保持五官、发型、发色、服饰和体型，不能仅凭文字重新设计人物。
- 缺少立绘的人物不自行补画；参考图无法使用时报告失败，不退化为无参考重画。
- 参考副本最长边1536像素以控制耗时，原立绘文件不修改；立绘内容更换时生成缓存自动失效。
- 这是模型参考约束，不能保证所有角度和每次生成都达到像素级身份一致。仅支持非露骨场景与完整着装人物。

## 公开图片 API（仅手动选择的备用通道）

仅在环境变量中明确设置 `WORLD_SIM_BACKGROUND_PROVIDER=openai` 时才调用公开 Images API。
该通道需要 `OPENAI_API_KEY` 或优先级更高的 `WORLD_SIM_OPENAI_IMAGE_API_KEY`，独立于 DeepSeek/旧 `image_key.py`。
默认模型 `gpt-image-2.5-flare`，可通过 `WORLD_SIM_OPENAI_IMAGE_MODEL` 更改。
该备用通道目前只支持无人物参考的背景生成，收到立绘参考会报错，不会忽略立绘。
网络继承环境/系统代理；`NO_PROXY` 可添加 `localhost,127.0.0.1` 排除本地桥接。

## 速度与显示

- Codex 默认仅生成一张图，并请求低质量、最小支持的横向尺寸；具体分辨率以内置工具实际输出为准。
- 只发送短场景、最新情节与相关立绘，不发送完整对话历史和世界观限制提示词。
- 相同请求在桥接内缓存5分钟，最多8张；缓存键包含立绘内容。不做自动生图重试。
- 图片请求使用独立的 HTTPRequest，不占用文字请求或输入锁。忙时最多保留一个最新待处理请求，过期图片不会覆盖新回复对应的背景。
- 10秒无法保证，本机首次普通背景测试也花费数十秒。Codex 任务最长等待180秒，前端195秒；超时结束本项目启动的任务，背景不变。
- 保留生成图原始分辨率，仅在显示时缩放，不把图片永久缩成界面槽位大小。

## 保存与读档

每张成功背景先自动保存为 `game/picture/session/scenes/<地点>.png`，并替换当前地点的图片缓存。
普通存档会将它一并复制到 `game/saves/slot_1/resources/scenes/`；读档从该目录恢复。

如果当前游戏已经存档或读档，且磁盘存档没有被其他操作更换，生成完成后会自动更新那个存档中已有地点的背景资源，
不会自动重写游戏进度 JSON。新游戏、新地点首次仍需手动存档，避免覆盖另一个游戏时间线的进度。
读档或新游戏会取消尚未完成的生图请求，防止上一条时间线的响应污染当前存档。

## 验证

Python 接口单元测试（模拟进程/API，不真实生图）：

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -p 'test_*image_service.py' -v
```

Godot 本地模拟链路（在另一终端启动模拟服务，再执行检查）：

```powershell
.\.venv\Scripts\python.exe tests/fake_instant_image_server.py
& 'D:\Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script tests/instant_background_check.gd
```

模拟服务只监听 `127.0.0.1:18769`。结束后关闭该终端或访问 `http://127.0.0.1:18769/shutdown`。
测试使用独立的 `user://instant_background_check_*` 目录，不修改真实存档和设置。

参数依据：[OpenAI 图片生成说明](https://developers.openai.com/api/docs/guides/image-generation)、
[Images API 参数](https://developers.openai.com/api/reference/resources/images/methods/generate)。
