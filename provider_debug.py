"""Provider failure diagnostics, without keys or conversation contents."""
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import re
import socket
import ssl
import subprocess
import sys
import traceback
from datetime import datetime, timezone
from urllib.parse import urlsplit, urlunsplit
import uuid


def safe_url(value):
    try:
        parsed = urlsplit(str(value))
        host = parsed.hostname or ""
        if ":" in host:
            host = "[" + host + "]"
        if parsed.port:
            host += ":" + str(parsed.port)
        return urlunsplit((parsed.scheme, host, parsed.path, "", ""))
    except ValueError:
        return "[invalid URL]"


def redact(text, secrets=()):
    value = str(text)
    sensitive = list(secrets)
    for name, configured in os.environ.items():
        if any(word in name.upper() for word in ("KEY", "TOKEN", "PASSWORD", "SECRET")):
            sensitive.append(configured)
        if "PROXY" in name.upper():
            try:
                parsed = urlsplit(configured)
                sensitive.extend((parsed.username, parsed.password))
            except ValueError:
                pass
    for secret in sorted({str(s) for s in sensitive if s}, key=len, reverse=True):
        value = value.replace(secret, "[REDACTED]")
    value = re.sub(r"(?i)(https?://)[^\s/@]+@", r"\1[REDACTED]@", value)
    value = re.sub(r"(?i)(bearer\s+)[^\s\"',}]+", r"\1[REDACTED]", value)
    value = re.sub(r"sk-[A-Za-z0-9_-]+", "[REDACTED]", value)
    value = re.sub(r"(?i)([?&](?:key|api_key|token|access_token|password)=)[^&\s\"']+", r"\1[REDACTED]", value)
    return value


def exception_details(error, secrets=()):
    chain = []
    seen = set()
    current = error
    while current is not None and id(current) not in seen:
        seen.add(id(current))
        entry = {"type": type(current).__module__ + "." + type(current).__name__,
                 "message": redact(str(current), secrets),
                 "repr": redact(repr(current), secrets)}
        for name in ("errno", "winerror", "status_code"):
            value = getattr(current, name, None)
            if value is not None:
                entry[name] = value
        req = getattr(current, "request", None)
        if req is not None:
            entry["request"] = {"method": str(req.method), "url": safe_url(req.url)}
        response = getattr(current, "response", None)
        if response is not None:
            entry["http_status"] = response.status_code
            entry["request_id"] = response.headers.get("x-request-id", "")
        chain.append(entry)
        current = current.__cause__ or (None if current.__suppress_context__ else current.__context__)
    return {"exception_chain": chain,
            "traceback": redact("".join(traceback.format_exception(type(error), error, error.__traceback__)), secrets)}


def _emit(value):
    print(json.dumps(value, ensure_ascii=True), flush=True)


def network_probe(endpoint):
    """Runs in a bounded child process; no credentials or prompts are sent."""
    parsed = urlsplit(endpoint)
    host, port = parsed.hostname, parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        addresses = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
        _emit({"stage": "dns", "host": host, "addresses": list(dict.fromkeys(str(a[4][0]) for a in addresses))})
    except Exception as error:
        _emit({"stage": "dns", **exception_details(error)})
        return
    for family, socktype, protocol, _, address in addresses[:2]:
        stage = "tcp"
        try:
            with socket.socket(family, socktype, protocol) as sock:
                sock.settimeout(1.5)
                sock.connect(address)
                _emit({"stage": stage, "address": address, "ok": True})
                if parsed.scheme == "https":
                    stage = "tls"
                    with ssl.create_default_context().wrap_socket(sock, server_hostname=host) as tls:
                        _emit({"stage": stage, "address": address, "ok": True, "version": tls.version()})
        except Exception as error:
            _emit({"stage": stage, "address": address, "ok": False, **exception_details(error)})
    import httpx
    for trust_env in (True, False):
        try:
            with httpx.Client(trust_env=trust_env, timeout=1.5) as client:
                response = client.get(endpoint.rstrip("/") + "/models")
                _emit({"stage": "https_models_without_key", "trust_env": trust_env,
                       "status": response.status_code, "note": "401/403 also proves HTTP reachability; no API key sent"})
        except Exception as error:
            _emit({"stage": "https_models_without_key", "trust_env": trust_env, **exception_details(error)})


def collect_network_probe(endpoint, secrets=()):
    try:
        result = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--probe", safe_url(endpoint)],
                                capture_output=True, text=True, encoding="utf-8", timeout=8,
                                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        return {"output": redact(result.stdout, secrets), "stderr": redact(result.stderr, secrets), "exit_code": result.returncode}
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        return {"output": redact(output, secrets), "note": "probe stopped after 8 seconds; completed stages retained"}
    except Exception as error:
        return exception_details(error, secrets)


def write_failure_report(error, context, attempts=(), secrets=()):
    root = Path(__file__).resolve().parent
    report_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    environment = {}
    for name in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "WORLD_SIM_HTTP_PROXY",
                 "WORLD_SIM_HTTPS_PROXY", "SSL_CERT_FILE", "SSL_CERT_DIR", "REQUESTS_CA_BUNDLE"):
        value = os.getenv(name, "")
        environment[name] = safe_url(value) if "PROXY" in name and name != "NO_PROXY" and value else value
    system_proxy = {}
    if os.name == "nt":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Internet Settings") as settings:
                for name in ("ProxyEnable", "ProxyServer", "AutoConfigURL"):
                    try:
                        system_proxy[name] = winreg.QueryValueEx(settings, name)[0]
                    except OSError:
                        pass
        except Exception as registry_error:
            system_proxy["read_error"] = str(registry_error)
    packages = {}
    for name in ("openai", "httpx", "httpcore", "requests", "certifi"):
        try:
            packages[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            packages[name] = "not installed"
    report = {"report_id": report_id, "utc": datetime.now(timezone.utc).isoformat(),
              "context": context, "attempts": list(attempts), **exception_details(error, secrets),
              "runtime": {"pid": os.getpid(), "ppid": os.getppid(), "python": sys.executable,
                          "version": sys.version, "cwd": str(Path.cwd()), "script": str(root / "chat.py"),
                          "script_sha256": hashlib.sha256((root / "chat.py").read_bytes()).hexdigest(),
                          "packages": packages},
              "proxy_and_cert_environment": environment, "windows_system_proxy": system_proxy,
              "note": "The chat client tries direct access first and then the environment/system-proxy route. Probes do not disable TLS validation or send keys."}
    directory = root / "logs" / "network"
    path = directory / (report_id + ".json")
    def save():
        body = redact(json.dumps(report, ensure_ascii=False, indent=2, default=str), secrets)
        try:
            directory.mkdir(parents=True, exist_ok=True)
            path.write_text(body, encoding="utf-8")
            (directory / "latest.json").write_text(body, encoding="utf-8")
        except OSError as file_error:
            report["file_error"] = str(file_error)
        return body
    save()  # Persist the exception even if later probes are interrupted.
    report["network_probe"] = collect_network_probe(context.get("endpoint", ""), secrets)
    body = save()
    print("[PROVIDER_DEBUG] " + body, flush=True)
    return {"debug_id": report_id, "debug_file": str(path), "debug_report": body}


if __name__ == "__main__" and len(sys.argv) == 3 and sys.argv[1] == "--probe":
    network_probe(sys.argv[2])
