# DeepSeek 桥接（chat.py）是怎么接进来的

## 链路

```
Godot 游戏 ──HTTP──▶ chat.py（本地 Flask，127.0.0.1:5000）──HTTPS──▶ api.deepseek.com
```

Godot 不直接请求 DeepSeek：密钥只保存在 Python 侧的 `key.py` / `image_key.py`，
提示词拼装、工具调用解析、最小字数补齐、生图转发都在 `chat.py` 里完成。
所以 `api.deepseek.com` 这个地址在 `game/` 里只出现一次，而且是给 Python 子进程
准备环境变量用的。

## 相关文件

| 文件 | 职责 |
| --- | --- |
| `chat.py` | 本地后端：`/chat`（文本+工具调用）、`/generate_image`、`/health` 等 |
| `key.py` / `image_key.py` | 密钥，只有 Python 读取 |
| `game/scripts/deepseek_service_manager.gd` | 启动器：确保 5000 端口上有“当前版本”的桥接在跑 |
| `game/scripts/game.gd` | `chat_url = http://127.0.0.1:5000/chat`，所有对话/行动请求发往这里 |
| `game/scripts/main_menu.gd` | 启动自检：调用 `/check_chat_service`、`/check_image_service` |

## 启动器做什么

1. 设置 `WORLD_SIM_CHAT_MODE=openai`、`WORLD_SIM_API_BASE_URL`（默认 `https://api.deepseek.com`）；
2. 探测 `/health`：能应答且是当前版本 → 直接复用（例如你自己在终端里启动的 `chat.py`）；
3. 若端口上是**旧版残留**或模式不符的桥接 → 用 `/health` 里的 `pid` 结束它，再启动新的；
4. 没有桥接时用 `.venv/Scripts/python.exe chat.py` 启动，最多等 45 秒；
5. 启动后再次确认应答 `/health` 的确实是自己拉起来的进程（Windows 允许两个
   `chat.py` 同时监听同一端口，残留的那个会让一部分请求返回 5xx）；
6. 退出游戏时结束自己启动的桥接进程。

## /health 契约（改这里要同步改两边）

`chat.py` 的 `/health` 返回：

```json
{
  "status": "healthy",
  "chat_mode": "openai",
  "protocol": 2,
  "version": "2",
  "pid": 12345,
  "ppid": 6789,
  "api_base_url": "https://api.deepseek.com",
  "model": "deepseek-v4-flash",
  "image_mode": "cloud"
}
```

- `protocol`：启动器要求 `>= REQUIRED_BRIDGE_PROTOCOL`（当前 2）。版本落后 = 残留进程，会被结束。
- `pid`：真正运行 `chat.py` 的解释器进程。
- `ppid`：Windows 上 `.venv/Scripts/python.exe` 只是启动器，它会派生出真正的解释器；
  Godot 用 `create_process` 拿到的是启动器的 pid，所以两个都要报。
- 修改 `BRIDGE_PROTOCOL` / `REQUIRED_BRIDGE_PROTOCOL` 时必须同步。

## 常用环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `WORLD_SIM_CHAT_MODE` | `openai` | `openai` / `ollama` |
| `WORLD_SIM_API_BASE_URL` | `https://api.deepseek.com` | 换源改这里 |
| `WORLD_SIM_MODEL` | `deepseek-v4-flash` | 模型名 |
| `WORLD_SIM_PROVIDER_ATTEMPTS` | `3` | 单端点重试次数（连接类错误才重试） |
| `WORLD_SIM_PROVIDER_TIMEOUT` | `45` | 单次请求超时（秒） |
| `WORLD_SIM_HTTP_PROXY` / `WORLD_SIM_HTTPS_PROXY` | 空 | 需要代理时才设置 |

## 出问题时看哪里

- 游戏日志出现 `[DEEPSEEK] …`：启动器对桥接的判断过程都在这里；
  `桥接已就绪（pid=…，model=…，端点=…）` 说明用的是哪个进程、哪个端点。
- 界面/日志出现 `服务器错误 <码>：<原因>`：`502` 表示桥接在，但请求模型失败
  （密钥、端点或本机网络/代理问题），具体原因随响应一起显示。
- 想手动重启桥接：关掉游戏后执行
  `.\.venv\Scripts\python.exe chat.py`；游戏启动时会复用这个进程。
