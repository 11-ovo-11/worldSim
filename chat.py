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
SDXL_ENGINE_ID = "gpt-image-1-mini"
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
                text = message.content
                # 如果有工具调用，转换为字典列表
                if message.tool_calls is not None:
                    text = [tool_call.model_dump() for tool_call in message.tool_calls]
                print("ai:", text)
                return jsonify({"text": text})
            except Exception as e:
                print(f"DeepSeek API请求失败: {str(e)}")
                return jsonify({"error": f"DeepSeek API请求失败: {str(e)}"}), 533
                
        case _:
            return jsonify({"error": f"不支持的聊天模式: {chat_mode}"}), 400

@app.route("/generate_image", methods=["POST"])
def generate_image():

    req_data = request.get_json()

    prompt = req_data.get("prompt", "")
    width = int(req_data.get("width", 1024))
    height = int(req_data.get("height", 1024))

    if not prompt:
        return jsonify({
            "success": False,
            "error": "提示词不能为空"
        }), 400

    if not image_key:
        return jsonify({"success": False, "error": "未配置 image_key",
                        "debug": {"exception": "image_key is empty"}}), 500

    try:

        response = requests.post(
            "https://api.vectorengine.ai/v1/images/generations",
            headers={
                "Authorization": f"Bearer {image_key}",
                "Content-Type": "application/json"
            },
            json={
                "model": "grok-imagine-image-pro",
                "prompt": prompt,
                "size": f"{width}x{height}"
            },
            timeout=180
        )

        print("[IMG_DEBUG] status =", response.status_code)
        print("[IMG_DEBUG] body =", response.text[:500])

        if response.status_code != 200:
            return jsonify({
                "success": False,
                "error": response.text
            }), 500

        data = response.json()

        items = data.get("data", [])

        if not items:
            return jsonify({
                "success": False,
                "error": "API未返回图片"
            }), 500

        image_url = items[0].get("url")

        if not image_url:
            return jsonify({
                "success": False,
                "error": "未找到图片URL"
            }), 500

        print("[IMG_DEBUG] downloading image:", image_url)

        # 下载图片
        img_response = requests.get(
            image_url,
            timeout=120
        )

        if img_response.status_code != 200:
            return jsonify({
                "success": False,
                "error": "图片下载失败"
            }), 500

        # 转base64
        image_base64 = base64.b64encode(
            img_response.content
        ).decode("utf-8")

        print("[IMG_DEBUG] image downloaded, b64 len =", len(image_base64))

        # 返回给Godot（兼容旧结构）
        return jsonify({
            "success": True,
            "image": image_base64,
            "provider": "vectorengine",
            "model": "grok-imagine-image-pro"
        })

    except Exception as e:

        print("[IMG_DEBUG] exception =", str(e))

        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


@app.route("/test_image", methods=["GET"])
def test_image():
    """快速测试图片生成，返回完整调试信息"""
    test_prompt = "a simple red apple on white background"
    size = "1024x1024"
    target_url = "https://api.vectorengine.ai/v1/images/generations"
    print(f"[TEST_IMAGE] POST {target_url} model={SDXL_ENGINE_ID}")
    result = {"url": target_url, "model": SDXL_ENGINE_ID, "key_prefix": (image_key or "")[:8] + "..."}
    if not image_key:
        result["error"] = "image_key 未配置"
        return jsonify(result), 500
    try:
        resp = requests.post(
            target_url,
            headers={"Authorization": f"Bearer {image_key}", "Content-Type": "application/json"},
            json={"model": SDXL_ENGINE_ID, "prompt": test_prompt, "size": size},
            timeout=120
        )
        result["status"] = resp.status_code
        result["body_preview"] = resp.text[:800]
        if resp.status_code == 200:
            data = resp.json()
            items = data.get("data", [])
            if items:
                img_url = items[0].get("url", "")
                result["img_url"] = img_url
                if img_url:
                    dl = requests.get(img_url, timeout=60)
                    result["dl_status"] = dl.status_code
                    result["dl_bytes"] = len(dl.content)
                    result["success"] = dl.status_code == 200
                else:
                    b64 = items[0].get("b64_json", "")
                    result["b64_len"] = len(b64)
                    result["success"] = bool(b64)
            else:
                result["error"] = "响应中没有data字段"
        else:
            result["error"] = f"HTTP {resp.status_code}"
    except Exception as e:
        result["error"] = str(e)
    print(f"[TEST_IMAGE] result={result}")
    return jsonify(result)

@app.route("/test_chat", methods=["GET"])
def test_chat():
    """快速测试AI文本生成，返回完整调试信息"""
    result = {"chat_mode": chat_mode}
    try:
        client = OpenAI(api_key=key, base_url=provider_base_url)
        resp = client.chat.completions.create(
            model=model_name,
            messages=[{"role": "user", "content": "用一句话证明你已运行"}],
            max_tokens=50
        )
        result["text"] = resp.choices[0].message.content
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