"""Background routing: Codex CLI by default; explicit OpenAI API fallback."""
import base64
import binascii
import hashlib
import os
import time
from collections import OrderedDict
from threading import Lock

import requests

DEFAULT_MODEL = "gpt-image-2.5-flare"
IMAGE_SIZE = "1024x640"  # Minimum documented pixel budget: 655,360.
TIMEOUT_SECONDS = 25
_cache = OrderedDict()
_cache_lock = Lock()


def _api_key():
    return (os.getenv("WORLD_SIM_OPENAI_IMAGE_API_KEY", "").strip()
            or os.getenv("OPENAI_API_KEY", "").strip())


def openai_configuration_status():
    """Local, free check; never return credentials or send a test generation."""
    configured = bool(_api_key())
    return {
        "provider": "openai",
        "model": os.getenv("WORLD_SIM_OPENAI_IMAGE_MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL,
        "configured": configured,
        "status": "configured" if configured else "not_configured",
        "message": "OpenAI 即时生图密钥已配置（可在设置中开启）" if configured else "即时生图尚未配置 OpenAI API 密钥；不影响文字对话",
        "size": IMAGE_SIZE,
        "quality": "low",
        "target_seconds": 10,
        "timeout_seconds": TIMEOUT_SECONDS,
    }


def generate_openai_background(data, post=None):
    """Return (JSON payload, HTTP status); one paid request, no blind retries."""
    started = time.monotonic()
    config = openai_configuration_status()
    key = _api_key()
    if not key:
        return {"success": False, "error": "即时生图未配置 OpenAI API 密钥。请在本机设置 OPENAI_API_KEY 后重启游戏。", **config}, 503
    if not isinstance(data, dict):
        return {"success": False, "error": "图片请求必须是 JSON 对象。"}, 400
    prompt = str(data.get("prompt", "")).strip()[:1400]
    target = str(data.get("target_name", "")).strip()[:100]
    if not prompt or not target:
        return {"success": False, "error": "缺少场景或图片提示词。"}, 400
    model = config["model"]
    # Older GPT Image models require standard sizes; never lower quality by
    # stretching a tiny unsupported image, or silently substitute providers.
    size = IMAGE_SIZE if model.startswith(("gpt-image-2",)) else "1536x1024"
    cache_key = hashlib.sha256((model + size + prompt).encode("utf-8")).hexdigest()
    with _cache_lock:
        cached = _cache.get(cache_key)
        if cached and time.monotonic() - cached[0] < 300:
            _cache.move_to_end(cache_key)
            return {**cached[1], "target_name": target, "cached": True, "elapsed_ms": 0}, 200
    payload = {
        "model": model, "prompt": prompt, "n": 1, "size": size,
        "quality": "low", "output_format": "jpeg", "output_compression": 75,
        "background": "opaque",
    }
    request_id = ""
    try:
        # The official endpoint is kept separate from the DeepSeek base URL.
        # requests honors the user's environment/system proxy configuration.
        response = (post or requests.post)(
            "https://api.openai.com/v1/images/generations",
            headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
            json=payload, timeout=(4, TIMEOUT_SECONDS), allow_redirects=False,
        )
        request_id = response.headers.get("x-request-id", "")
        if response.status_code != 200:
            try:
                error = response.json().get("error", {})
                message = error.get("message", "") if isinstance(error, dict) else str(error)
            except (ValueError, AttributeError):
                message = ""
            message = str(message).replace(key, "[redacted]")[:600]
            status = response.status_code if response.status_code in (400, 401, 403, 429) else 502
            return {"success": False, "error": "OpenAI 生图失败：" + (message or "HTTP " + str(response.status_code)), "provider_request_id": request_id}, status
        result = response.json()
        items = result.get("data", [])
        encoded = str(items[0].get("b64_json", "")) if items else ""
        raw = base64.b64decode(encoded, validate=True)
        if not raw.startswith((b"\xff\xd8\xff", b"\x89PNG\r\n\x1a\n")):
            return {"success": False, "error": "图片接口未返回有效的 JPEG/PNG 图像。", "provider_request_id": request_id}, 502
        width, height = map(int, size.split("x"))
        answer = {
            "success": True, "image": encoded, "provider": "openai", "model": model,
            "target_type": "scene", "target_name": target, "width": width, "height": height,
            "elapsed_ms": round((time.monotonic() - started) * 1000),
            "provider_request_id": request_id, "cached": False,
        }
        with _cache_lock:
            _cache[cache_key] = (time.monotonic(), answer)
            while len(_cache) > 8:
                _cache.popitem(last=False)
        return answer, 200
    except requests.Timeout:
        return {"success": False, "error": "OpenAI 生图超时，已保留当前背景；可继续文字交互。"}, 504
    except (ValueError, TypeError, IndexError, AttributeError, binascii.Error):
        return {"success": False, "error": "图片接口响应格式不正确。", "provider_request_id": request_id}, 502
    except requests.RequestException as error:
        detail = str(error).replace(key, "[redacted]")[:400]
        return {"success": False, "error": "OpenAI 图片服务连接失败：" + detail}, 502


def configuration_status():
    if os.getenv("WORLD_SIM_BACKGROUND_PROVIDER", "codex_cli").strip().lower() == "openai":
        return openai_configuration_status()
    from codex_image_service import configuration_status as codex_status
    return codex_status()


def generate_background(data, post=None):
    if os.getenv("WORLD_SIM_BACKGROUND_PROVIDER", "codex_cli").strip().lower() == "openai":
        if isinstance(data, dict) and data.get("references"):
            return {"success": False, "error": "人物立绘绑定需要 Codex CLI 通道；当前公开 Images generations 通道不支持此绑定。"}, 400
        return generate_openai_background(data, post)
    from codex_image_service import generate_background as codex_generate
    return codex_generate(data)
