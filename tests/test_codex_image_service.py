import base64
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import codex_image_service as service
import instant_image_service as router

PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVQIHWP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")


class FakeProcess:
    returncode = 0
    pid = 123456

    def __init__(self, args, **kwargs):
        self.args = args
        self.kwargs = kwargs
        self.input = b""

    def communicate(self, input, timeout):
        self.input = input
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

    def test_invalid_portrait_does_not_launch(self):
        with patch.object(service.subprocess, "Popen") as start:
            answer, status = service.generate_background(self.request(b"not PNG"))
        self.assertEqual(status, 400)
        start.assert_not_called()

    def test_timeout_stops_own_job_and_releases_lock(self):
        class SlowProcess(FakeProcess):
            def communicate(self, **kwargs):
                raise subprocess.TimeoutExpired("test", 180)
        with patch.object(service.subprocess, "Popen", side_effect=SlowProcess), patch.object(service, "_stop_process") as stop:
            answer, status = service.generate_background(self.request())
        self.assertEqual(status, 504)
        stop.assert_called_once()
        self.assertFalse(service.generate_background.busy)
        self.assertEqual(list(Path(self.folder.name).iterdir()), [])

    def test_default_route_is_codex_not_public_images_api(self):
        with patch.dict("os.environ", {"WORLD_SIM_BACKGROUND_PROVIDER": "codex_cli"}), patch.object(service, "generate_background", return_value=({"success": True}, 200)) as generate:
            router.generate_background(self.request())
            generate.assert_called_once()

    def test_api_path_does_not_silently_drop_reference(self):
        with patch.dict("os.environ", {"WORLD_SIM_BACKGROUND_PROVIDER": "openai"}):
            answer, status = router.generate_background(self.request())
        self.assertEqual(status, 400)
        self.assertFalse(answer["success"])


if __name__ == "__main__":
    unittest.main()
