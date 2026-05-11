extends RefCounted
class_name GameHttpUtils

static func request_json(host: Node, url: String, body_json: String) -> Dictionary:
	var request_node := HTTPRequest.new()
	host.add_child(request_node)
	var err = request_node.request(
		url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body_json
	)
	if err != OK:
		request_node.queue_free()
		return {"ok": false, "error": "请求创建失败: " + str(err)}

	var response = await request_node.request_completed
	request_node.queue_free()

	var result: int = response[0]
	var response_code: int = response[1]
	var body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "网络错误: " + str(result)}

	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		return {"ok": false, "error": "响应解析失败"}

	var data = parser.get_data()
	if response_code != 200:
		return {"ok": false, "error": str(data.get("error", "HTTP " + str(response_code)))}
	return {"ok": true, "data": data}
