import base64
import os
import unittest
from unittest.mock import Mock, patch

import requests
import instant_image_service as service


class InstantImageTests(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {
            "OPENAI_API_KEY": "test-key-not-a-real-credential",
            "WORLD_SIM_OPENAI_IMAGE_API_KEY": "",
            "WORLD_SIM_OPENAI_IMAGE_MODEL": service.DEFAULT_MODEL,
            "WORLD_SIM_BACKGROUND_PROVIDER": "openai",
        })
        self.environment.start()
        service._cache.clear()

    def tearDown(self):
        self.environment.stop()

    def response(self, status=200, data=None):
        response = Mock(status_code=status, headers={"x-request-id": "test-request"})
        response.json.return_value = data or {"data": [{"b64_json": base64.b64encode(b"\xff\xd8\xfftest-jpeg").decode()}]}
        return response

    def test_low_latency_options_and_cache(self):
        post = Mock(return_value=self.response())
        result, code = service.generate_background({"prompt": "a quiet library", "target_name": "library"}, post)
        self.assertEqual(code, 200)
        self.assertEqual(result["target_type"], "scene")
        options = post.call_args.kwargs
        self.assertEqual(post.call_args.args[0], "https://api.openai.com/v1/images/generations")
        self.assertEqual(options["json"]["quality"], "low")
        self.assertEqual(options["json"]["size"], "1024x640")
        self.assertEqual(options["json"]["output_format"], "jpeg")
        self.assertEqual(options["json"]["n"], 1)
        self.assertFalse(options["allow_redirects"])
        again, code = service.generate_background({"prompt": "a quiet library", "target_name": "new-name"}, post)
        self.assertTrue(again["cached"])
        self.assertEqual(again["target_name"], "new-name")
        self.assertEqual(post.call_count, 1)

    def test_missing_key_does_not_request(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "", "WORLD_SIM_OPENAI_IMAGE_API_KEY": ""}):
            post = Mock()
            answer, code = service.generate_background({"prompt": "library", "target_name": "library"}, post)
            self.assertEqual(code, 503)
            self.assertFalse(answer["configured"])
            post.assert_not_called()

    def test_error_preserved_but_secret_redacted(self):
        key = os.environ["OPENAI_API_KEY"]
        post = Mock(return_value=self.response(403, {"error": {"message": "denied " + key}}))
        answer, code = service.generate_background({"prompt": "library", "target_name": "library"}, post)
        self.assertEqual(code, 403)
        self.assertNotIn(key, answer["error"])
        self.assertIn("denied", answer["error"])
        self.assertEqual(post.call_count, 1)

    def test_timeout_and_corrupt_response(self):
        request = {"prompt": "library", "target_name": "library"}
        answer, code = service.generate_background(request, Mock(side_effect=requests.Timeout()))
        self.assertEqual(code, 504)
        self.assertFalse(answer["success"])
        answer, code = service.generate_background(request, Mock(return_value=self.response(200, {"data": []})))
        self.assertEqual(code, 502)
        answer, code = service.generate_background(request, Mock(return_value=self.response(200, {"data": [{"b64_json": "bad-base64"}]})))
        self.assertEqual(code, 502)

    def test_input_limits_and_standard_model_size(self):
        post = Mock(return_value=self.response())
        with patch.dict(os.environ, {"WORLD_SIM_OPENAI_IMAGE_MODEL": "gpt-image-1-mini"}):
            service.generate_background({"prompt": "a" * 4000, "target_name": "library", "width": 8000}, post)
        self.assertEqual(post.call_args.kwargs["json"]["size"], "1536x1024")
        self.assertEqual(len(post.call_args.kwargs["json"]["prompt"]), 4000)
        self.assertEqual(service.generate_background({"prompt": "a" * 12001, "target_name": "library"}, post)[1], 400)
        self.assertEqual(service.generate_background(None, post)[1], 400)
        self.assertEqual(service.generate_background({}, post)[1], 400)

    def test_flask_routes_and_bridge_version(self):
        import chat
        client = chat.app.test_client()
        with patch.object(chat, "generate_background", return_value=({"success": True, "image": "test"}, 200)) as generate:
            result = client.post("/generate_instant_background", json={"prompt": "library", "target_name": "library"})
            self.assertEqual(result.status_code, 200)
            generate.assert_called_once()
        status = client.get("/instant_image_status").get_json()
        self.assertTrue(status["configured"])
        self.assertNotIn(os.environ["OPENAI_API_KEY"], str(status))
        self.assertEqual(client.get("/health").get_json()["protocol"], 8)
        from 生图诊断 import emit
        emit("fixture", "进度", "测试进度")
        debug = client.get("/instant_image_debug?after=0").get_json()
        self.assertTrue(any(row["request_id"] == "fixture" for row in debug["events"]))
        self.assertEqual(client.get('/instant_image_debug?after=' + str(debug['cursor'])).get_json()["events"], [])


if __name__ == "__main__":
    unittest.main()
