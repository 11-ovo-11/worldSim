"""Bounded image progress and read-only Codex quota queries; no prompt/secret dumps."""
from collections import deque
import json
import os
from queue import Queue, Empty
import subprocess
from threading import Lock, Thread
import time
import uuid

from provider_debug import redact

_lock = Lock()
_events = deque(maxlen=300)
_sequence = 0
_instance = uuid.uuid4().hex
_quota = {"status": "not_requested", "message": "账户额度尚未查询"}
_quota_at = 0.0
_quota_busy = False


def emit(request_id, phase, message):
    global _sequence
    with _lock:
        _sequence += 1
        _events.append({"seq": _sequence, "request_id": str(request_id)[:80],
                        "phase": phase, "message": redact(message)[:4000], "time": time.time()})


def snapshot(after=0):
    with _lock:
        return {"instance": _instance, "cursor": _sequence,
                "events": [dict(event) for event in _events if event["seq"] > after],
                "quota": dict(_quota)}


def normalize_limits(result):
    buckets = result.get("rateLimitsByLimitId") or {"codex": result.get("rateLimits")}
    rows = []
    for key, bucket in buckets.items():
        if not isinstance(bucket, dict):
            continue
        windows = []
        for window_key in ("primary", "secondary"):
            window = bucket.get(window_key)
            if isinstance(window, dict) and isinstance(window.get("usedPercent"), (int, float)):
                used = window["usedPercent"]
                windows.append({"used_percent": used, "remaining_percent": max(0, 100 - used),
                                "window_minutes": window.get("windowDurationMins"), "resets_at": window.get("resetsAt")})
        if windows:
            rows.append({"name": str(bucket.get("limitName") or key)[:80], "windows": windows})
    return {"status": "available" if rows else "unavailable", "limits": rows,
            "message": "账户共享额度窗口，不能当作单张图片扣费" if rows else "服务未返回可显示的账户额度",
            "checked_at": time.time()}


def read_limits(command, timeout=12):
    """Initialize app-server, read limits only, then close it; never log in/out or reset credits."""
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    process = subprocess.Popen(command + ["app-server", "--stdio"], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               creationflags=flags)
    inbox = Queue()
    def receive():
        for line in process.stdout:
            try:
                inbox.put(json.loads(line))
            except (ValueError, UnicodeError):
                continue
        inbox.put(None)
    reader = Thread(target=receive, daemon=True)
    reader.start()
    deadline = time.monotonic() + timeout
    def send(value):
        process.stdin.write((json.dumps(value) + "\n").encode())
        process.stdin.flush()
    def reply(identifier):
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("额度查询超时")
            try:
                value = inbox.get(timeout=remaining)
            except Empty as error:
                raise TimeoutError("额度查询超时") from error
            if value is None:
                raise RuntimeError("额度查询进程已退出")
            if value.get("id") == identifier:
                if value.get("error"):
                    raise RuntimeError(str(value["error"].get("message", "账户额度不可读取")))
                return value.get("result", {})
    try:
        send({"method": "initialize", "id": 1, "params": {"clientInfo": {"name": "worldsim_quota", "version": "1.0"}}})
        reply(1)
        send({"method": "initialized"})
        send({"method": "account/rateLimits/read", "id": 2})
        return normalize_limits(reply(2))
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               creationflags=flags, timeout=5, check=False)
            else:
                process.kill()
            process.wait(timeout=5)
        reader.join(timeout=1)
        process.stdout.close()


def refresh_quota(command):
    """At most one bounded query per minute, off the image generation path."""
    global _quota_busy, _quota_at, _quota
    with _lock:
        if _quota_busy or (_quota_at and time.monotonic() - _quota_at < 60):
            return
        _quota_busy = True
        _quota = {**_quota, "status": "loading", "message": "正在查询账户额度"}
    def run():
        global _quota_busy, _quota_at, _quota
        try:
            result = read_limits(command) if command else {"status": "unavailable", "message": "未找到Codex CLI"}
        except Exception as error:
            result = {"status": "unavailable", "message": "额度不可读取：" + redact(str(error))[:300]}
        with _lock:
            _quota = result
            _quota_at = time.monotonic()
            _quota_busy = False
    Thread(target=run, daemon=True).start()
