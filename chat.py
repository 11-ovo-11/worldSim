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
from key import key
from image_key import image_key
IMAGE_MODE = "cloud"  # 可选 "local" 或 "cloud"
STABILITY_API_HOST = os.getenv("API_HOST", "https://api.stability.ai")
SDXL_ENGINE_ID = "stable-diffusion-xl-1024-v1-0"
# 初始化 Flask 应用
app = Flask(__name__)
CORS(app)

# DeepSeek 配置
DEEP_SEEK_KEY = key
clientOpenAI = OpenAI(
    api_key=DEEP_SEEK_KEY,
    base_url="https://api.deepseek.com"
)

#def comfy_headers():
   # headers = {"Content-Type": "application/json"}
  #  if COMFYUI_API_KEY:
   #     headers["Authorization"] = f"Bearer {COMFYUI_API_KEY}"
   # return headers

# 原有的 Ollama 配置
OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "deepseek-v2:16b"
AGENT_MODEL_NAME = "qwen3:8b"
chat_mode = "openai"

# ComfyUI 配置
#COMFYUI_URL = "https://your-comfyui-api.com"
#COMFYUI_API_KEY = "你的APIKEY"  # 如果不需要可以设为 None


# 全局变量，用于缓存工作流和客户端
workflow_cache = {}
workflow_lock = Lock()

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
                    model="deepseek-chat",
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
    data = request.get_json()
    prompt = data.get("prompt", "")
    width = data.get("width", 1024)
    height = data.get("height", 1024)
    steps = int(data.get("steps", 30))
    cfg_scale = float(data.get("cfg_scale", 7))
    mode = data.get("mode", "default")

    if not prompt:
        return jsonify({"success": False, "error": "提示词不能为空"}), 400

    if not image_key:
        return jsonify({"success": False, "error": "未配置 image_key"}), 500

    # 允许的分辨率组合（官方规定）
    allowed_sizes = [
        (1024, 1024),
        (1152, 896),
        (896, 1152),
        (1216, 832),
        (1344, 768),
        (768, 1344),
        (1536, 640),
        (640, 1536),
    ]

    if (width, height) not in allowed_sizes:
        return jsonify({
            "success": False,
            "error": f"不支持的分辨率 {width}x{height}"
        }), 400

    # 允许调用端按需调低参数提升速度
    if mode == "ultra_fast_item":
        steps = max(4, min(20, steps))
        cfg_scale = max(1.0, min(12.0, cfg_scale))
    else:
        steps = max(10, min(40, steps))
        cfg_scale = max(1.0, min(20.0, cfg_scale))

    try:
        response = requests.post(
            f"{STABILITY_API_HOST}/v1/generation/{SDXL_ENGINE_ID}/text-to-image",
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Authorization": f"Bearer {image_key}"
            },
            json={
                "text_prompts": [
                    {
                        "text": prompt
                    }
                ],
                "cfg_scale": cfg_scale,
                "height": height,
                "width": width,
                "samples": 1,
                "steps": steps
            },
            timeout=60
        )

        if response.status_code != 200:
            return jsonify({
                "success": False,
                "error": response.text
            }), response.status_code

        data = response.json()

        image_base64 = data["artifacts"][0]["base64"]

        return jsonify({
            "success": True,
            "image": image_base64,
            "model": "sdxl-1.0",
            "provider": "stability-ai"
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


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
        # 通过 Stability API 引擎列表做连通性检查
        response = requests.get(
            f"{STABILITY_API_HOST}/v1/engines/list",
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {image_key}"
            },
            timeout=8
        )

        if response.status_code == 200:
            engines = response.json() if response.text else []
            has_sdxl = any(engine.get("id") == SDXL_ENGINE_ID for engine in engines if isinstance(engine, dict))
            balance_msg = ""
            try:
                acc_resp = requests.get(
                    f"{STABILITY_API_HOST}/v1/user/account",
                    headers={"Accept": "application/json", "Authorization": f"Bearer {image_key}"},
                    timeout=8
                )
                if acc_resp.status_code == 200:
                    acc_data = acc_resp.json()
                    credits = acc_data.get("credits", None)
                    if credits is not None:
                        balance_msg = "，余额" + str(round(float(credits), 2)) + "点"
            except Exception:
                pass
            return jsonify({
                "status": "connected",
                "message": "视觉模块已连接" + balance_msg,
                "service": "Stability AI",
                "engine": SDXL_ENGINE_ID,
                "engine_available": has_sdxl
            })
        else:
            return jsonify({
                "status": "disconnected",
                "message": "视觉模块连接异常",
                "service": "Stability AI",
                "error": f"HTTP {response.status_code}"
            }), 503
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
                    model="deepseek-chat",
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
                        "service": "DeepSeek API",
                        "model": "deepseek-chat"
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
        "chat_mode": chat_mode
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