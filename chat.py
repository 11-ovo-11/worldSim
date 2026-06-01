from flask import Flask, request, jsonify
import requests
import base64
import time
import json
import uuid
from flask_cors import CORS
from threading import Lock
import os 
import openai
from openai import OpenAI
import gc
from key import key
from image_key import image_key
IMAGE_MODE = "cloud"  # 可选 "local" 或 "cloud"
STABILITY_API_HOST ="https://api.vectorengine.cn"
#https://api.vectorengine.cn
#https://api.vectorengine.cn/v1
#https://api.vectorengine.cn/v1/chat/completions
#https://api.vectorengine.ai/v1
#https://api.vectorengine.ai
SDXL_ENGINE_ID = "grok-3-image"
#stable-diffusion-xl-1024-v1-0
# 初始化 Flask 应用
app = Flask(__name__)
CORS(app)

# ==================== API 提供商配置（换源时只改这里）====================
# base_url 示例：
#   DeepSeek : https://api.deepseek.com
#   SiliconFlow: https://api.siliconflow.cn/v1
#   Moonshot  : https://api.moonshot.cn/v1
#   OpenAI    : https://api.openai.com/v1
#   Qwen      : https://dashscope.aliyuncs.com/compatible-mode/v1
API_BASE_URL = "https://api.deepseek.com"#"https://api.vectorengine.ai/v1"
# model 示例：deepseek-chat / deepseek-r1 / Qwen/Qwen3-30B-A3B / moonshot-v1-8k
API_MODEL_CHAT ="deepseek-v4-flash"
# =========================================================================

DEEP_SEEK_KEY = key
clientOpenAI = OpenAI(
    api_key=DEEP_SEEK_KEY,
    base_url=API_BASE_URL
)

#def comfy_headers():
   # headers = {"Content-Type": "application/json"}
  #  if COMFYUI_API_KEY:
   #     headers["Authorization"] = f"Bearer {COMFYUI_API_KEY}"
   # return headers

# 原有的 Ollama 配置
OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "deepseek-v4-flash"#"deepseek-v4-pro"
AGENT_MODEL_NAME = "qwen3:8b"
chat_mode = "openai"
CHAT_RESTART_THRESHOLD = int(os.getenv("CHAT_RESTART_THRESHOLD", "300"))
CHAT_REQUEST_COUNT = 0
LAST_RUNTIME_RECYCLE_AT = 0.0

# ComfyUI 配置
#COMFYUI_URL = "https://your-comfyui-api.com"
#COMFYUI_API_KEY = "你的APIKEY"  # 如果不需要可以设为 None


# 全局变量，用于缓存工作流和客户端
workflow_cache = {}
workflow_lock = Lock()

IMAGE_API_FALLBACK_HOSTS = [
    "https://api.vectorengine.ai",
    STABILITY_API_HOST,
]

IMAGE_REQUEST_TIMEOUT_SECONDS = float(os.getenv("IMAGE_REQUEST_TIMEOUT_SECONDS", "60"))
IMAGE_PREFLIGHT_TTL_SECONDS = int(os.getenv("IMAGE_PREFLIGHT_TTL_SECONDS", "30"))
IMAGE_PREFLIGHT_ENABLED = str(os.getenv("IMAGE_PREFLIGHT_ENABLED", "0")).strip().lower() in ["1", "true", "yes", "on"]
_IMAGE_PREFLIGHT_CACHE = {
    "checked_at": 0.0,
    "ok": False,
    "reason": "",
    "endpoint": "",
    "debug": {},
}


def _truncate_text(text: str, limit: int = 300) -> str:
    src = str(text or "")
    if len(src) <= limit:
        return src
    return src[:limit] + "..."


def _extract_error_message(raw_text: str) -> str:
    text = str(raw_text or "").strip()
    if text == "":
        return ""
    try:
        obj = json.loads(text)
    except Exception:
        return _truncate_text(text, 500)
    if isinstance(obj, dict):
        err = obj.get("error", "")
        if isinstance(err, dict):
            msg = str(err.get("message", "")).strip()
            err_type = str(err.get("type", "")).strip()
            if msg != "" and err_type != "":
                return msg + f" [type={err_type}]"
            if msg != "":
                return msg
            if err_type != "":
                return err_type
        if isinstance(err, str) and err.strip() != "":
            return err.strip()
        msg2 = str(obj.get("message", "")).strip()
        if msg2 != "":
            return msg2
    return _truncate_text(text, 500)


def _is_hard_image_failure(status_code: int, message: str) -> bool:
    msg = str(message or "").lower()
    if status_code in (401, 403):
        return True
    hard_keywords = [
        "额度已用尽", "insufficient", "quota", "余额不足",
        "invalid api key", "unauthorized", "forbidden", "model_not_found",
        "does not exist", "not available", "permission denied"
    ]
    for kw in hard_keywords:
        if kw in msg:
            return True
    return False


def _load_image_api_hosts() -> list:
    raw_hosts = str(os.getenv("IMAGE_API_HOSTS", "")).strip()
    hosts = []
    if raw_hosts != "":
        for h in raw_hosts.split(","):
            hh = h.strip()
            if hh != "" and hh not in hosts:
                hosts.append(hh)
    for default_host in IMAGE_API_FALLBACK_HOSTS:
        hh = str(default_host).strip()
        if hh != "" and hh not in hosts:
            hosts.append(hh)
    return hosts

def _build_image_endpoint_candidates() -> list:
    endpoints = []
    for host in _load_image_api_hosts():
        clean_host = str(host).strip().rstrip("/")
        if clean_host == "":
            continue
        endpoint = clean_host + "/v1/images/generations"
        if endpoint not in endpoints:
            endpoints.append(endpoint)
    return endpoints


def _probe_image_generation_once() -> dict:
    endpoints = _build_image_endpoint_candidates()
    attempts = []
    test_payload = {
        "model": SDXL_ENGINE_ID,
        "prompt": "simple daylight campus scene, no text",
        "size": "1024x1024"
    }
    for endpoint in endpoints:
        start_at = time.time()
        try:
            resp = requests.post(
                endpoint,
                headers={
                    "Authorization": f"Bearer {image_key}",
                    "Content-Type": "application/json"
                },
                json=test_payload,
                timeout=IMAGE_REQUEST_TIMEOUT_SECONDS
            )
            elapsed_ms = int((time.time() - start_at) * 1000)
            preview = _truncate_text(resp.text, 500)
            reason = _extract_error_message(preview)
            attempt = {
                "endpoint": endpoint,
                "status_code": resp.status_code,
                "elapsed_ms": elapsed_ms,
                "reason": reason,
            }
            attempts.append(attempt)
            print(f"[IMG_PREFLIGHT] endpoint={endpoint} status={resp.status_code} elapsed_ms={elapsed_ms} reason={_truncate_text(reason, 200)}")
            if resp.status_code == 200:
                try:
                    data = resp.json()
                except Exception:
                    continue
                items = data.get("data", [])
                if isinstance(items, list) and len(items) > 0:
                    has_url = str(items[0].get("url", "")).strip() != ""
                    has_b64 = str(items[0].get("b64_json", "")).strip() != ""
                    if has_url or has_b64:
                        return {
                            "ok": True,
                            "endpoint": endpoint,
                            "reason": "",
                            "debug": {"attempts": attempts}
                        }
            if _is_hard_image_failure(resp.status_code, reason):
                return {
                    "ok": False,
                    "endpoint": endpoint,
                    "reason": reason if reason != "" else f"HTTP {resp.status_code}",
                    "debug": {"attempts": attempts}
                }
        except Exception as e:
            elapsed_ms = int((time.time() - start_at) * 1000)
            reason = str(e)
            attempts.append({
                "endpoint": endpoint,
                "elapsed_ms": elapsed_ms,
                "reason": reason,
            })
            print(f"[IMG_PREFLIGHT] endpoint={endpoint} exception={reason} elapsed_ms={elapsed_ms}")
    final_reason = "图片试生成失败：所有端点均不可用"
    if attempts:
        last_reason = str(attempts[-1].get("reason", "")).strip()
        if last_reason != "":
            final_reason = last_reason
    return {
        "ok": False,
        "endpoint": "",
        "reason": final_reason,
        "debug": {"attempts": attempts}
    }


def _ensure_image_preflight(force: bool = False) -> dict:
    now = time.time()
    age = now - float(_IMAGE_PREFLIGHT_CACHE.get("checked_at", 0.0))
    if (not force) and age >= 0 and age < IMAGE_PREFLIGHT_TTL_SECONDS:
        return {
            "ok": bool(_IMAGE_PREFLIGHT_CACHE.get("ok", False)),
            "endpoint": str(_IMAGE_PREFLIGHT_CACHE.get("endpoint", "")),
            "reason": str(_IMAGE_PREFLIGHT_CACHE.get("reason", "")),
            "debug": dict(_IMAGE_PREFLIGHT_CACHE.get("debug", {})),
            "cached": True,
            "cache_age": int(age)
        }
    result = _probe_image_generation_once()
    _IMAGE_PREFLIGHT_CACHE["checked_at"] = now
    _IMAGE_PREFLIGHT_CACHE["ok"] = bool(result.get("ok", False))
    _IMAGE_PREFLIGHT_CACHE["reason"] = str(result.get("reason", ""))
    _IMAGE_PREFLIGHT_CACHE["endpoint"] = str(result.get("endpoint", ""))
    _IMAGE_PREFLIGHT_CACHE["debug"] = dict(result.get("debug", {}))
    result["cached"] = False
    result["cache_age"] = 0
    return result

def _build_image_size_candidates(target_type: str, width: int, height: int) -> list:
    requested = (max(1, int(width)), max(1, int(height)))
    presets = {
        "scene": [(1344, 768), (1536, 1024), (1024, 1024)],
        "npc": [(1024, 1536), (896, 1152), (1024, 1024)],
        "item": [(1024, 1024)],
    }
    candidates = []
    for size in [requested] + presets.get(target_type, presets["scene"]):
        if size not in candidates:
            candidates.append(size)
    return candidates

def _rebuild_openai_client():
    global clientOpenAI
    clientOpenAI = OpenAI(
        api_key=DEEP_SEEK_KEY,
        base_url=API_BASE_URL
    )

def _maybe_recycle_runtime(force: bool = False, reason: str = ""):
    global CHAT_REQUEST_COUNT, LAST_RUNTIME_RECYCLE_AT, workflow_cache
    if not force and CHAT_REQUEST_COUNT < CHAT_RESTART_THRESHOLD:
        return False
    with workflow_lock:
        workflow_cache.clear()
    _rebuild_openai_client()
    gc.collect()
    LAST_RUNTIME_RECYCLE_AT = time.time()
    CHAT_REQUEST_COUNT = 0
    print(f"[RUNTIME_RECYCLE] done reason={reason}, ts={LAST_RUNTIME_RECYCLE_AT}")
    return True

# 基础工作流模板 - 只定义一次
BASE_WORKFLOW = {
    "3": {
        "inputs": {
            "seed": 156680208700286,
            "steps": 23,
            "cfg": 10,
            "sampler_name": "euler",
            "scheduler": "normal",
            "denoise": 1,
            "model": ["4", 0],
            "positive": ["6", 0],
            "negative": ["7", 0],
            "latent_image": ["5", 0]
        },
        "class_type": "KSampler",
        "_meta": {"title": "K采样器"}
    },
    "4": {
        "inputs": {
            "ckpt_name": "my\\sd_xl_turbo_1.0_fp16.safetensors"
        },
        "class_type": "CheckpointLoaderSimple",
        "_meta": {"title": "Checkpoint加载器(简易)"}
    },
    "5": {
        "inputs": {
            "width": 512,
            "height": 256,
            "batch_size": 1
        },
        "class_type": "EmptyLatentImage",
        "_meta": {"title": "空Latent"}
    },
    "6": {
        "inputs": {
            "text": "beautiful scenery",  # 占位符，会被动态替换
            "clip": ["4", 1]
        },
        "class_type": "CLIPTextEncode",
        "_meta": {"title": "CLIP文本编码器"}
    },
    "7": {
        "inputs": {
            "text": "text, watermark, people, dark",
            "clip": ["4", 1]
        },
        "class_type": "CLIPTextEncode",
        "_meta": {"title": "CLIP文本编码器"}
    },
    "8": {
        "inputs": {
            "samples": ["3", 0],
            "vae": ["4", 2]
        },
        "class_type": "VAEDecode",
        "_meta": {"title": "VAE解码"}
    },
    "9": {
        "inputs": {
            "filename_prefix": "worldSim",
            "images": ["8", 0]
        },
        "class_type": "SaveImage",
        "_meta": {"title": "保存图像"}
    }
}

def get_cached_workflow():
    """获取或创建缓存的工作流"""
    with workflow_lock:
        if 'workflow' not in workflow_cache:
            # 深度复制基础工作流
            workflow_cache['workflow'] = json.loads(json.dumps(BASE_WORKFLOW))
        return workflow_cache['workflow']

@app.route("/chat", methods=["POST"])
def chat():
    global CHAT_REQUEST_COUNT
    CHAT_REQUEST_COUNT += 1
    _maybe_recycle_runtime(False, "chat_threshold")
    user_msg = request.get_json()[0]
    tools = request.get_json()[1]
    output_format = request.get_json()[2]
    if not user_msg:
        return jsonify({"error": "消息不能为空"}), 400
        
    match chat_mode:
        case "ollama":
            payload = {
                "model": MODEL_NAME,
                "prompt": user_msg,

                "stream": False
            }

            try:
                r = requests.post(OLLAMA_URL, json=payload)
                r.raise_for_status()
                j = r.json()
                text = j.get("response", "")
                print("文本生成完成")
                return jsonify({"text": text})
            except Exception as e:
                return jsonify({"error": f"Ollama请求失败: {str(e)}"}), 500
                
        case "openai":
            print("发起了一次openai请求：", user_msg)
            try:
                response = clientOpenAI.chat.completions.create(
                    model=API_MODEL_CHAT,
                    messages=user_msg,
                    tools=tools,
                    response_format = { "type": output_format } ,
                    stream=False
                )
                # 获取消息
                message = response.choices[0].message
                text = message.content if message.content is not None else ""
                tool_calls = []
                if message.tool_calls is not None:
                    tool_calls = [tool_call.model_dump() for tool_call in message.tool_calls]
                print("ai:", {"text": text, "tool_calls": tool_calls})
                return jsonify({"text": text, "tool_calls": tool_calls})
            except Exception as e:
                print(f"DeepSeek API请求失败: {str(e)}")
                return jsonify({"error": f"DeepSeek API请求失败: {str(e)}"}), 533
                
        case _:
            return jsonify({"error": f"不支持的聊天模式: {chat_mode}"}), 400

@app.route("/generate_image", methods=["POST"])
def generate_image():

    req_data = request.get_json(silent=True) or {}

    prompt = str(req_data.get("prompt", "")).strip()
    width = int(req_data.get("width", 1024))
    height = int(req_data.get("height", 1024))
    target_type = str(req_data.get("target_type", "scene")).strip().lower()
    target_name = str(req_data.get("target_name", "")).strip()

    if not prompt:
        return jsonify({
            "success": False,
            "error": "提示词不能为空"
        }), 400

    if not image_key:
        return jsonify({"success": False, "error": "未配置 image_key",
                        "debug": {"exception": "image_key is empty"}}), 500

    if IMAGE_PREFLIGHT_ENABLED:
        preflight = _ensure_image_preflight(False)
        if not preflight.get("ok", False):
            reason = str(preflight.get("reason", "图片试生成失败")).strip()
            print(f"[IMG_DEBUG] preflight failed: {reason}")
            return jsonify({
                "success": False,
                "error": "图片试生成失败：" + (reason if reason != "" else "未知原因"),
                "debug": {
                    "stage": "preflight",
                    "cached": bool(preflight.get("cached", False)),
                    "cache_age": int(preflight.get("cache_age", 0)),
                    "endpoint": str(preflight.get("endpoint", "")),
                    "attempts": preflight.get("debug", {}).get("attempts", []),
                    "model": SDXL_ENGINE_ID,
                }
            }), 503

    endpoints = _build_image_endpoint_candidates()
    sizes = _build_image_size_candidates(target_type, width, height)
    attempts = []

    try:
        for endpoint in endpoints:
            for candidate in sizes:
                size_text = f"{candidate[0]}x{candidate[1]}"
                print(f"[IMG_DEBUG] POST {endpoint} target_type={target_type} target_name={target_name} size={size_text} model={SDXL_ENGINE_ID} prompt_len={len(prompt)}")
                try:
                    response = requests.post(
                        endpoint,
                        headers={
                            "Authorization": f"Bearer {image_key}",
                            "Content-Type": "application/json"
                        },
                        json={
                            "model": SDXL_ENGINE_ID,
                            "prompt": prompt,
                            "size": size_text
                        },
                        timeout=IMAGE_REQUEST_TIMEOUT_SECONDS
                    )
                except Exception as request_error:
                    attempt = {
                        "endpoint": endpoint,
                        "size": size_text,
                        "exception": str(request_error)
                    }
                    attempts.append(attempt)
                    print(f"[IMG_DEBUG] request exception endpoint={endpoint} size={size_text} error={request_error}")
                    continue

                body_preview = _truncate_text(response.text, 500)
                reason = _extract_error_message(body_preview)
                attempts.append({
                    "endpoint": endpoint,
                    "size": size_text,
                    "status_code": response.status_code,
                    "reason": reason,
                    "response_preview": body_preview,
                })
                print(f"[IMG_DEBUG] attempt status={response.status_code} endpoint={endpoint} size={size_text} reason={_truncate_text(reason, 200)}")

                if response.status_code != 200:
                    if _is_hard_image_failure(response.status_code, reason):
                        return jsonify({
                            "success": False,
                            "error": reason if reason != "" else f"HTTP {response.status_code}",
                            "debug": {
                                "stage": "request",
                                "target_type": target_type,
                                "target_name": target_name,
                                "endpoint": endpoint,
                                "attempts": attempts,
                                "model": SDXL_ENGINE_ID,
                            }
                        }), 502
                    continue

                try:
                    data = response.json()
                except Exception:
                    continue
                items = data.get("data", [])
                if not items:
                    continue

                image_url = str(items[0].get("url", "")).strip()
                image_base64 = str(items[0].get("b64_json", "")).strip()

                if image_url != "":
                    print("[IMG_DEBUG] downloading image:", image_url)
                    img_response = requests.get(image_url, timeout=120)
                    if img_response.status_code != 200:
                        attempts.append({
                            "endpoint": endpoint,
                            "size": size_text,
                            "download_status": img_response.status_code,
                            "download_url": image_url,
                        })
                        continue
                    image_base64 = base64.b64encode(img_response.content).decode("utf-8")

                if image_base64 == "":
                    continue

                print("[IMG_DEBUG] image ready, b64 len =", len(image_base64))
                return jsonify({
                    "success": True,
                    "image": image_base64,
                    "provider": "vectorengine",
                    "model": SDXL_ENGINE_ID,
                    "target_type": target_type,
                    "target_name": target_name,
                    "width": candidate[0],
                    "height": candidate[1],
                })

        last_error = attempts[-1] if attempts else {}
        return jsonify({
            "success": False,
            "error": str(last_error.get("reason", last_error.get("exception", last_error.get("response_preview", "图片生成失败")))),
            "debug": {
                "target_type": target_type,
                "target_name": target_name,
                "attempts": attempts,
                "model": SDXL_ENGINE_ID,
            }
        }), 500

    except Exception as e:

        print("[IMG_DEBUG] exception =", str(e))

        return jsonify({
            "success": False,
            "error": str(e),
            "debug": {
                "target_type": target_type,
                "target_name": target_name,
                "model": SDXL_ENGINE_ID,
                "exception": str(e),
            }
        }), 500


@app.route("/test_image", methods=["GET"])
def test_image():
    """快速测试图片生成，返回完整调试信息"""
    test_prompt = "a simple red apple on white background"
    result = {"endpoints": _build_image_endpoint_candidates(), "model": SDXL_ENGINE_ID, "key_prefix": (image_key or "")[:8] + "..."}
    if not image_key:
        result["error"] = "image_key 未配置"
        return jsonify(result), 500
    try:
        result["attempts"] = []
        for endpoint in _build_image_endpoint_candidates():
            resp = requests.post(
                endpoint,
                headers={"Authorization": f"Bearer {image_key}", "Content-Type": "application/json"},
                json={"model": SDXL_ENGINE_ID, "prompt": test_prompt, "size": "1024x1024"},
                timeout=120
            )
            attempt = {
                "endpoint": endpoint,
                "status": resp.status_code,
                "body_preview": resp.text[:800]
            }
            result["attempts"].append(attempt)
            if resp.status_code != 200:
                continue
            data = resp.json()
            items = data.get("data", [])
            if not items:
                continue
            img_url = str(items[0].get("url", "")).strip()
            if img_url != "":
                dl = requests.get(img_url, timeout=60)
                attempt["img_url"] = img_url
                attempt["dl_status"] = dl.status_code
                attempt["dl_bytes"] = len(dl.content)
                result["success"] = dl.status_code == 200
                if dl.status_code == 200:
                    break
            else:
                b64 = str(items[0].get("b64_json", "")).strip()
                attempt["b64_len"] = len(b64)
                result["success"] = b64 != ""
                if b64 != "":
                    break
        if not result.get("success", False):
            result["error"] = "所有测试端点均失败"
    except Exception as e:
        result["error"] = str(e)
    print(f"[TEST_IMAGE] result={result}")
    return jsonify(result)

@app.route("/test_chat", methods=["GET"])
def test_chat():
    """快速测试AI文本生成，返回完整调试信息"""
    result = {"chat_mode": chat_mode}
    try:
        client = OpenAI(api_key=key, base_url=API_BASE_URL)
        resp = client.chat.completions.create(
            model=API_MODEL_CHAT,
            messages=[{"role": "user", "content": "用一句话证明你已运行"}],
            max_tokens=50
        )
        result["text"] = resp.choices[0].message.content
        result["base_url"] = API_BASE_URL
        result["model"] = API_MODEL_CHAT
        result["success"] = True
    except Exception as e:
        result["error"] = str(e)
        result["success"] = False
    print(f"[TEST_CHAT] result={result}")
    return jsonify(result)

@app.route("/health", methods=["GET"])
def health_check():
    """健康检查端点"""
    return jsonify({"status": "healthy", "chat_mode": chat_mode})

@app.route("/", methods=["GET"])
def index():
    """服务首页，避免浏览器访问根路径返回 404"""
    return jsonify({
        "message": "worldSim chat server is running",
        "endpoints": [
            "/health",
            "/check_image_service",
            "/check_chat_service",
            "/service_status",
            "/chat",
            "/generate_image"
        ]
    })

# 新增的服务状态检查端点
@app.route("/check_image_service", methods=["GET"])
def check_image_service():
    """检查图片生成服务连接状态"""
    if not image_key:
        return jsonify({
            "status": "misconfigured",
            "message": "未配置 image_key",
            "service": "Stability AI"
        }), 500

    try:
        # 仅做连通性检查，不依赖 Stability 专有端点，兼容任何代理
        response = requests.get(
            STABILITY_API_HOST + "/",
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {image_key}"
            },
            timeout=8
        )
        # 能收到任何 HTTP 响应（含 4xx/5xx）均视为服务可达
        return jsonify({
            "status": "connected",
            "message": "视觉模块已连接",
            "service": "Stability AI",
            "engine": SDXL_ENGINE_ID,
            "engine_available": True
        })
    except requests.exceptions.ConnectionError:
        return jsonify({
            "status": "disconnected",
            "message": "视觉模块未连接",
            "service": "Stability AI",
            "error": "无法连接到服务"
        }), 503
    except requests.exceptions.Timeout:
        return jsonify({
            "status": "timeout",
            "message": "视觉模块连接超时",
            "service": "Stability AI",
            "error": "连接超时"
        }), 503
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": "视觉模块检查失败",
            "service": "Stability AI",
            "error": str(e)
        }), 500

@app.route("/check_chat_service", methods=["GET"])
def check_chat_service():
    """检查问答生成服务连接状态"""
    try:
        match chat_mode:
            case "ollama":
                # 检查Ollama服务
                response = requests.get("http://localhost:11434/api/tags", timeout=10)
                if response.status_code == 200:
                    return jsonify({
                        "status": "connected",
                        "message": "神经网络已连接",
                        "service": "Ollama",
                        "model": MODEL_NAME
                    })
                else:
                    return jsonify({
                        "status": "disconnected",
                        "message": "神经网络连接异常",
                        "service": "Ollama",
                        "error": f"HTTP {response.status_code}"
                    }), 503
                    
            case "openai":
                # 检查DeepSeek API服务
                # 发送一个简单的测试请求
                test_response = clientOpenAI.chat.completions.create(
                    model=API_MODEL_CHAT,
                    messages=[{"role": "user", "content": "测试连接"}],
                    max_tokens=5,
                    stream=False
                )
                if test_response.choices:
                    balance_msg = ""
                    try:
                        bal_resp = requests.get(
                            "https://api.deepseek.com/user/balance",
                            headers={"Authorization": f"Bearer {DEEP_SEEK_KEY}", "Accept": "application/json"},
                            timeout=8
                        )
                        if bal_resp.status_code == 200:
                            bal_data = bal_resp.json()
                            infos = bal_data.get("balance_infos", [])
                            for info in infos:
                                if info.get("currency") == "CNY":
                                    balance_msg = "，余额" + info.get("total_balance", "?") + "元"
                                    break
                    except Exception:
                        pass
                    return jsonify({
                        "status": "connected",
                        "message": "神经网络已连接" + balance_msg,
                        "service": API_BASE_URL,
                        "model": API_MODEL_CHAT
                    })
                else:
                    return jsonify({
                        "status": "disconnected",
                        "message": "神经网络响应异常",
                        "service": "DeepSeek API",
                        "error": "无响应内容"
                    }), 503
                    
            case _:
                return jsonify({
                    "status": "unknown",
                    "message": "未知的聊天模式",
                    "service": "Unknown",
                    "error": f"不支持的聊天模式: {chat_mode}"
                }), 400
                
    except requests.exceptions.ConnectionError:
        return jsonify({
            "status": "disconnected",
            "message": "神经网络未连接",
            "service": chat_mode,
            "error": "无法连接到服务"
        }), 503
    except requests.exceptions.Timeout:
        return jsonify({
            "status": "timeout",
            "message": "神经网络连接超时",
            "service": chat_mode,
            "error": "连接超时"
        }), 503
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": "神经网络检查失败",
            "service": chat_mode,
            "error": str(e)
        }), 500

# 新增的完整服务状态检查端点
@app.route("/service_status", methods=["GET"])
def service_status():
    """检查所有服务的完整状态"""
    def _extract_status_data(status_result):
        # 兼容 Flask 视图函数返回值：Response / tuple / str 等，统一转为 Response
        response_obj = app.make_response(status_result)
        data = response_obj.get_json(silent=True)
        return data if isinstance(data, dict) else {}

    image_data = _extract_status_data(check_image_service())
    chat_data = _extract_status_data(check_chat_service())
    
    return jsonify({
        "image_service": image_data,
        "chat_service": chat_data,
        "timestamp": time.time(),
        "chat_mode": chat_mode,
        "runtime": {
            "chat_request_count": CHAT_REQUEST_COUNT,
            "chat_restart_threshold": CHAT_RESTART_THRESHOLD,
            "last_runtime_recycle_at": LAST_RUNTIME_RECYCLE_AT
        }
    })

if __name__ == "__main__":
    from waitress import serve
    print("启动服务器在 http://127.0.0.1:5000")
    print("服务器已进入监听状态（这是常驻进程，不会自动退出）。")
    print("服务状态检查端点:")
    print("  GET / - 服务首页")
    print("  GET /health - 健康检查")
    print("  GET /check_image_service - 检查图片生成服务")
    print("  GET /check_chat_service - 检查问答生成服务") 
    print("  GET /service_status - 检查所有服务状态")
    print("按 Ctrl+C 停止服务")
    serve(app, host="127.0.0.1", port=5000)