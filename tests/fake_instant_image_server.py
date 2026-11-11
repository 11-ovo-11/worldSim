"""Local-only Godot integration fixture. No cloud calls, credentials, or cost."""
import argparse
import base64
import json
import struct
import threading
import time
import zlib
from urllib.parse import urlsplit, parse_qs

EVENTS = []
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def png(red, green, blue):
    def chunk(kind, body):
        return struct.pack("!I", len(body)) + kind + body + struct.pack("!I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!2I5B", 1, 1, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes([0, red, green, blue]))) + chunk(b"IEND", b""))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def answer(self, data, code=200):
        body = json.dumps(data).encode()
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass

    def do_GET(self):
        if self.path.startswith("/instant_image_debug"):
            after = int(parse_qs(urlsplit(self.path).query).get("after", ["0"])[0])
            self.answer({"instance": "fixture", "cursor": len(EVENTS), "events": [row for row in EVENTS if row["seq"] > after],
                         "quota": {"status": "available", "limits": [{"name": "codex", "windows": [{"window_minutes": 300, "used_percent": 37, "remaining_percent": 63}]}]}})
        else:
            self.answer({"ok": True})
        if self.path == "/shutdown":
            threading.Thread(target=self.server.shutdown, daemon=True).start()

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        prompt = data["prompt"]
        EVENTS.append({"seq": len(EVENTS) + 1, "request_id": data.get("request_id", ""), "phase": "模拟生成", "message": "已接收立绘与场景"})
        time.sleep(0.35 if "慢请求" in prompt else 0.04)
        if "失败请求" in prompt:
            self.answer({"success": False, "error": "fixture-failure"}, 503)
            return
        color = (0, 255, 0) if "最新请求" in prompt else (255, 0, 0)
        self.answer({"success": True, "image": base64.b64encode(png(*color)).decode(),
                     "target_type": "scene", "target_name": data["target_name"], "usage": {"images_generated": 1, "tokens": {"input_tokens": 80, "cached_input_tokens": 40, "output_tokens": 12}, "cost": None}})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18769)
    server = ThreadingHTTPServer(("127.0.0.1", parser.parse_args().port), Handler)
    print("FAKE_IMAGE_SERVER_READY", server.server_address[1], flush=True)
    server.serve_forever()
