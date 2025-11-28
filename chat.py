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
# 初始化 Flask 应用
app = Flask(__name__)
CORS(app)

# DeepSeek 配置
DEEP_SEEK_KEY = key
clientOpenAI = OpenAI(
    api_key=DEEP_SEEK_KEY,
    base_url="https://api.deepseek.com"
)

# 原有的 Ollama 配置
OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "deepseek-v2:16b"
AGENT_MODEL_NAME = "qwen3:8b"
chat_mode = "openai"

# ComfyUI 配置
COMFYUI_URL = "http://localhost:8188"

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
    print("开始生成图片")
    data = request.get_json()
    prompt = data.get("prompt", "")
    
    if not prompt:
        return jsonify({"success": False, "error": "提示词不能为空"}), 400

    try:
        # 从缓存获取工作流，只更新必要的部分
        workflow = get_cached_workflow()
        
        # 只更新正向提示词和种子
        workflow["6"]["inputs"]["text"] = prompt+",photography"
        workflow["3"]["inputs"]["seed"] = int(time.time() % (10**9))

        payload = {
            "prompt": workflow
        }
        
        # 提交生成任务
        response = requests.post(f"{COMFYUI_URL}/api/prompt", json=payload)
        response.raise_for_status()
        prompt_response = response.json()
        prompt_id = prompt_response["prompt_id"]
        
        # 轮询检查任务状态
        max_attempts = 120
        attempts = 0
        
        while attempts < max_attempts:
            time.sleep(1)
            
            history_response = requests.get(f"{COMFYUI_URL}/history/{prompt_id}")
            history_data = history_response.json()
            
            if prompt_id in history_data:
                # 任务完成，获取图片
                output_images = history_data[prompt_id]["outputs"]
                for node_id, node_output in output_images.items():
                    if "images" in node_output:
                        image_info = node_output["images"][0]
                        image_response = requests.get(
                            f"{COMFYUI_URL}/view?filename={image_info['filename']}" +
                            f"&subfolder={image_info.get('subfolder', '')}" +
                            f"&type={image_info['type']}"
                        )
                        if image_response.status_code == 200:
                            image_base64 = base64.b64encode(image_response.content).decode('utf-8')
                            return jsonify({
                                "success": True,
                                "image": image_base64,
                                "info": "图片生成成功",
                                "prompt_id": prompt_id
                            })
                return jsonify({"success": False, "error": "生成结果中未找到图片"}), 500
            
            attempts += 1
        
        # 超时处理
        return jsonify({
            "success": False, 
            "error": f"生成超时，请在 ComfyUI 界面检查任务状态。prompt_id: {prompt_id}"
        }), 408
                
    except requests.exceptions.ConnectionError:
        return jsonify({
            "success": False, 
            "error": "无法连接到 ComfyUI 服务，请确保 ComfyUI 正在运行在 http://localhost:8188"
        }), 503
    except Exception as e:
        return jsonify({
            "success": False, 
            "error": f"生成图片时出错: {str(e)}"
        }), 500

@app.route("/health", methods=["GET"])
def health_check():
    """健康检查端点"""
    return jsonify({"status": "healthy", "chat_mode": chat_mode})

# 新增的服务状态检查端点
@app.route("/check_image_service", methods=["GET"])
def check_image_service():
    """检查图片生成服务连接状态"""
    try:
        # 尝试连接到ComfyUI服务
        response = requests.get(f"{COMFYUI_URL}/api/system_stats", timeout=5)
        if response.status_code == 200:
            return jsonify({
                "status": "connected",
                "message": "视觉模块已连接",
                "service": "ComfyUI"
            })
        else:
            return jsonify({
                "status": "disconnected",
                "message": "视觉模块连接异常",
                "service": "ComfyUI",
                "error": f"HTTP {response.status_code}"
            }), 503
    except requests.exceptions.ConnectionError:
        return jsonify({
            "status": "disconnected",
            "message": "视觉模块未连接",
            "service": "ComfyUI",
            "error": "无法连接到服务"
        }), 503
    except requests.exceptions.Timeout:
        return jsonify({
            "status": "timeout",
            "message": "视觉模块连接超时",
            "service": "ComfyUI",
            "error": "连接超时"
        }), 503
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": "视觉模块检查失败",
            "service": "ComfyUI",
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
                    return jsonify({
                        "status": "connected",
                        "message": "神经网络已连接",
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
    image_status = check_image_service()
    chat_status = check_chat_service()
    
    # 解析响应数据
    image_data = image_status[0].get_json() if hasattr(image_status[0], 'get_json') else {}
    chat_data = chat_status[0].get_json() if hasattr(chat_status[0], 'get_json') else {}
    
    return jsonify({
        "image_service": image_data,
        "chat_service": chat_data,
        "timestamp": time.time(),
        "chat_mode": chat_mode
    })

if __name__ == "__main__":
    from waitress import serve
    print("启动服务器在 http://127.0.0.1:5000")
    print("服务状态检查端点:")
    print("  GET /check_image_service - 检查图片生成服务")
    print("  GET /check_chat_service - 检查问答生成服务") 
    print("  GET /service_status - 检查所有服务状态")
    serve(app, host="127.0.0.1", port=5000)