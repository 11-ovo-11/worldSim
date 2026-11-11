import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import codex_image_service as service
import instant_image_service as router
import 生图诊断 as diagnostics

CLI_COMMAND = service.cli_command

PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVQIHWP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")


class FakeProcess:
    returncode = 0
    pid = 123456

    def __init__(self, args, **kwargs):
        self.args = args
        self.kwargs = kwargs
        self.input = kwargs["stdin"].read()

    def communicate(self, timeout):
        job = Path(self.args[self.args.index("-C") + 1])
        (job / "background.png").write_bytes(PNG)


class CodexImageTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="worldsim-cli-test-")
        self.root_patch = patch.object(service, "JOB_ROOT", Path(self.folder.name))
        self.root_patch.start()
        self.cli_patch = patch.object(service, "cli_command", return_value=["node", "codex.js"])
        self.cli_patch.start()
        service._cache.clear()
        service.generate_background.busy = False

    def tearDown(self):
        self.cli_patch.stop()
        self.root_patch.stop()
        self.folder.cleanup()

    def request(self, image=PNG):
        return {"prompt": 'library; `do not execute`', "target_name": "library",
                "references": [{"name": "测试角色", "image": base64.b64encode(image).decode()}]}

    def test_cli_receives_reference_image_and_stdin_only(self):
        processes = []
        def start(args, **kwargs):
            instance = FakeProcess(args, **kwargs)
            processes.append(instance)
            return instance
        with patch.object(service.subprocess, "Popen", side_effect=start):
            answer, status = service.generate_background(self.request())
        self.assertEqual(status, 200)
        self.assertEqual(answer["provider"], "codex_cli")
        process = processes[0]
        self.assertIn("--image", process.args)
        self.assertIn("--ephemeral", process.args)
        self.assertNotIn("library; `do not execute`", " ".join(process.args))
        self.assertIn("测试角色", process.input.decode())
        self.assertIn("不能只将它们转述为文字", process.input.decode())
        self.assertIn('model_reasoning_effort="low"', process.args)
        self.assertIn('features.apps=false', process.args)
        self.assertNotEqual(process.kwargs["stdin"], subprocess.PIPE)
        self.assertNotIn("CODEX_APP_TOOLS_PIPE_PATH", process.kwargs["env"])
        self.assertEqual(base64.b64decode(answer["image"]), PNG)
        self.assertEqual(list(Path(self.folder.name).iterdir()), [])

    def test_cache_includes_portrait_content(self):
        with patch.object(service.subprocess, "Popen", side_effect=FakeProcess) as start:
            first, _ = service.generate_background(self.request())
            second, _ = service.generate_background(self.request())
            third, _ = service.generate_background(self.request(PNG + b"changed"))
        self.assertFalse(first["cached"])
        self.assertTrue(second["cached"])
        self.assertFalse(third["cached"])
        self.assertEqual(start.call_count, 2)

    def test_full_turn_reaches_cli_with_single_scene_selection(self):
        processes = []
        def start(args, **kwargs):
            instance = FakeProcess(args, **kwargs)
            processes.append(instance)
            return instance
        request = self.request()
        request["prompt"] = json.dumps({"本轮输入": "图书馆窗边递茶", "AI回复": "背景细节。" * 400 + "她双手递出蓝茶杯。" + "稍后走到花园。" * 100}, ensure_ascii=False)
        with patch.object(service.subprocess, "Popen", side_effect=start):
            self.assertEqual(service.generate_background(request)[1], 200)
        instructions = processes[0].input.decode()
        self.assertIn(request["prompt"], json.loads(instructions.split("\n", 1)[1])["scene_reference"])
        self.assertIn("只调用一次", instructions)
        self.assertIn("二者冲突时以输入为准", instructions)
        self.assertIn("立绘只绑定外观，不绑定姿势", instructions)

    def test_cache_includes_current_input(self):
        request = self.request()
        with patch.object(service.subprocess, "Popen", side_effect=FakeProcess) as start:
            service.generate_background(request)
            changed = {**request, "prompt": request["prompt"] + "双手递茶"}
            self.assertFalse(service.generate_background(changed)[0]["cached"])
        self.assertEqual(start.call_count, 2)

    def test_overlong_scene_is_rejected_without_silent_truncation(self):
        with patch.object(service.subprocess, "Popen") as start:
            self.assertEqual(service.generate_background({**self.request(), "prompt": "a" * 12001})[1], 400)
        start.assert_not_called()

    def test_invalid_portrait_does_not_launch(self):
        with patch.object(service.subprocess, "Popen") as start:
            answer, status = service.generate_background(self.request(b"not PNG"))
        self.assertEqual(status, 400)
        start.assert_not_called()

    def test_timeout_stops_own_job_and_releases_lock(self):
        class SlowProcess(FakeProcess):
            def communicate(self, **kwargs):
                raise subprocess.TimeoutExpired("test", 180)
        with patch.object(service.subprocess, "Popen", side_effect=SlowProcess), patch.object(service, "_stop_process") as stop, patch.object(service.time, "monotonic", side_effect=[0, 0, 200]):
            answer, status = service.generate_background(self.request())
        self.assertEqual(status, 504)
        stop.assert_called_once()
        self.assertFalse(service.generate_background.busy)
        self.assertEqual(list(Path(self.folder.name).iterdir()), [])

    def test_ready_image_returns_without_waiting_for_cli_final_text(self):
        class FinishedImageProcess(FakeProcess):
            def communicate(self, **kwargs):
                super().communicate(**kwargs)
                raise subprocess.TimeoutExpired("CLI final text still pending", 1)
        with patch.object(service.subprocess, "Popen", side_effect=FinishedImageProcess), patch.object(service, "_stop_process") as stop:
            answer, status = service.generate_background(self.request())
        self.assertEqual(status, 200)
        self.assertEqual(base64.b64decode(answer["image"]), PNG)
        stop.assert_called_once()
        self.assertFalse(service.generate_background.busy)

    def test_partially_written_image_is_not_returned(self):
        class PartialImageProcess(FakeProcess):
            def communicate(self, **kwargs):
                super().communicate(**kwargs)
                job = Path(self.args[self.args.index("-C") + 1])
                (job / "background.png").write_bytes(PNG[:-12])
                raise subprocess.TimeoutExpired("image still writing", 1)
        with patch.object(service.subprocess, "Popen", side_effect=PartialImageProcess), patch.object(service, "_stop_process"), patch.object(service.time, "monotonic", side_effect=[0, 0, 200]):
            answer, status = service.generate_background(self.request())
        self.assertEqual(status, 504)
        self.assertNotIn("image", answer)

    def test_real_process_with_completed_image_and_stalled_exit(self):
        # Local subprocess only: reproduce a CLI that has an image but never exits.
        script = (
            "import pathlib,sys,time; sys.stdin.buffer.read(); "
            "job=pathlib.Path(sys.argv[sys.argv.index('-C')+1]); "
            "(job/'background.png').write_bytes((job/'portrait-1.png').read_bytes()); "
            "time.sleep(30)"
        )
        with patch.object(service, "cli_command", return_value=[sys.executable, "-c", script]), patch.object(service, "TIMEOUT_SECONDS", 4):
            answer, status = service.generate_background(self.request())
        self.assertEqual(status, 200, answer)
        self.assertEqual(base64.b64decode(answer["image"]), PNG)
        self.assertLess(answer["elapsed_ms"], 10000)
        self.assertFalse(service.generate_background.busy)
        self.assertEqual(list(Path(self.folder.name).iterdir()), [])

    def test_slow_stdin_reader_does_not_block_progress_or_deadline(self):
        # On Windows communicate(input=large_text) can block on a full stdin
        # pipe before its timeout starts. A regular input file avoids that path.
        identifier = "12345678-1234-4321-8765-123456789abc"
        script = (
            "import sys,json,time; "
            "print(json.dumps({'type':'thread.started','thread_id':'" + identifier + "'}),flush=True); "
            "time.sleep(6); sys.stdin.buffer.read()"
        )
        before = diagnostics.snapshot()["cursor"]
        started = time.monotonic()
        with patch.object(service, "cli_command", return_value=[sys.executable, "-c", script]), patch.object(service, "TIMEOUT_SECONDS", 1.5):
            answer, status = service.generate_background({**self.request(), "prompt": "场景" * 3000})
        self.assertEqual(status, 504, answer)
        self.assertLess(time.monotonic() - started, 5)
        self.assertTrue(any(row["phase"] == "模型连接" for row in diagnostics.snapshot(before)["events"]))
        self.assertFalse(service.generate_background.busy)

    def test_independent_environment_preserves_auth_proxy_and_permissions(self):
        values = {"CODEX_APP_TOOLS_PIPE_PATH": "parent-pipe", "CODEX_THREAD_ID": "parent-thread",
                  "CODEX_HOME": self.folder.name, "HTTPS_PROXY": "http://proxy.example:1234",
                  "CODEX_PERMISSION_PROFILE": "managed-policy"}
        with patch.dict("os.environ", values):
            environment = service.image_task_environment()
        self.assertNotIn("CODEX_THREAD_ID", environment)
        self.assertNotIn("CODEX_APP_TOOLS_PIPE_PATH", environment)
        for name in ("CODEX_HOME", "HTTPS_PROXY", "CODEX_PERMISSION_PROFILE"):
            self.assertEqual(environment[name], values[name])

    def test_unrelated_mcp_disabled_without_changing_user_file(self):
        config = Path(self.folder.name) / "config.toml"
        original = 'model="keep-model"\n[mcp_servers.godot]\ncommand="godot"\n[mcp_servers.node_repl]\ncommand="node"\n'
        config.write_text(original, encoding="utf-8")
        with patch.dict("os.environ", {"CODEX_HOME": self.folder.name}):
            options = service.image_task_options()
        self.assertIn("mcp_servers.godot.enabled=false", options)
        self.assertIn("mcp_servers.node_repl.enabled=false", options)
        self.assertNotIn('model="keep-model"', options)
        self.assertEqual(config.read_text(encoding="utf-8"), original)

    def test_desktop_native_cli_is_preferred_when_present(self):
        native = Path(self.folder.name) / "codex.exe"
        native.write_bytes(b"test-placeholder")
        with patch.dict("os.environ", {"CODEX_APP_RUNTIME_CLI_PATH": str(native)}):
            self.assertEqual(CLI_COMMAND(), [str(native.resolve())])

    def test_default_route_is_codex_not_public_images_api(self):
        with patch.dict("os.environ", {"WORLD_SIM_BACKGROUND_PROVIDER": "codex_cli"}), patch.object(service, "generate_background", return_value=({"success": True}, 200)) as generate:
            router.generate_background(self.request())
            generate.assert_called_once()

    def test_reads_only_this_tasks_generated_image_before_copy(self):
        identifier = "12345678-1234-4321-8765-123456789abc"
        generated = Path(self.folder.name) / "codex" / "generated_images" / identifier
        generated.mkdir(parents=True)
        (generated / "call_test.png").write_bytes(PNG)
        job = Path(self.folder.name) / "job"
        job.mkdir()
        with patch.dict("os.environ", {"CODEX_HOME": str(Path(self.folder.name) / "codex")}):
            self.assertEqual(service._find_ready_image(job, {"thread_id": identifier}), PNG)
            (generated / "call_test.png").rename(generated / "exec-test.png")
            self.assertEqual(service._find_ready_image(job, {"thread_id": identifier}), PNG)
            self.assertIsNone(service._find_ready_image(job, {"thread_id": "some-other-thread"}))
            self.assertIsNone(service._find_ready_image(job, {"thread_id": "../../job"}))

    def test_progress_never_exposes_reasoning_or_keys(self):
        job = Path(self.folder.name)
        rows = [
            {"type": "item.completed", "item": {"type": "reasoning", "text": "PRIVATE_REASONING"}},
            {"type": "item.completed", "item": {"type": "error", "message": "Bearer secret-test-token"}},
            {"type": "turn.completed", "usage": {"input_tokens": 200, "cached_input_tokens": 100, "output_tokens": 20}},
        ]
        (job / "events.jsonl").write_text("\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8")
        cursor = diagnostics.snapshot()["cursor"]
        state = {}
        service._collect_progress(job, state, "progress-test")
        captured = json.dumps(diagnostics.snapshot(cursor))
        self.assertNotIn("PRIVATE_REASONING", captured)
        self.assertNotIn("secret-test-token", captured)
        self.assertEqual(state["usage"]["input_tokens"], 200)

    def test_account_limits_are_shared_windows_not_image_price(self):
        result = diagnostics.normalize_limits({"rateLimits": {"primary": {"usedPercent": 33, "windowDurationMins": 300, "resetsAt": 100}}})
        self.assertEqual(result["limits"][0]["windows"][0]["remaining_percent"], 67)
        self.assertNotIn("cost", result)

    def test_real_read_only_quota_rpc_handshake(self):
        script = (
            "import sys,json\n"
            "for line in sys.stdin:\n"
            " r=json.loads(line)\n"
            " if r['method']=='initialize': print(json.dumps({'id':r['id'],'result':{}}),flush=True)\n"
            " elif r['method']=='account/rateLimits/read': print(json.dumps({'id':r['id'],'result':{'rateLimits':{'primary':{'usedPercent':20,'windowDurationMins':300}}}}),flush=True)\n"
            " elif r['method']!='initialized': raise RuntimeError('unexpected write operation')\n"
        )
        result = diagnostics.read_limits([sys.executable, "-c", script], timeout=3)
        self.assertEqual(result["status"], "available")
        self.assertEqual(result["limits"][0]["windows"][0]["remaining_percent"], 80)

    def test_api_path_does_not_silently_drop_reference(self):
        with patch.dict("os.environ", {"WORLD_SIM_BACKGROUND_PROVIDER": "openai"}):
            answer, status = router.generate_background(self.request())
        self.assertEqual(status, 400)
        self.assertFalse(answer["success"])


if __name__ == "__main__":
    unittest.main()
