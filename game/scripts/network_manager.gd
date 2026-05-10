extends Node

# 网络管理
var chat_url = "http://127.0.0.1:5000/chat"
var agent_url = "http://127.0.0.1:5000/agent"
var image_api_url = "http://localhost:5000/generate_image"
@onready var http_request = $HTTPRequest

func send_chat_request(message, askmode):
    set_ai_busy(true)
    _ignore_next_request_completed = false
    if askmode == aiMode.init_background or askmode == aiMode.init_env:
        http_request.timeout = 0.0
    else:
        http_request.timeout = ai_request_timeout_seconds
    var outbound_messages = _compact_messages_for_request(_decorate_messages_for_output_mode(message, askmode))
    var body = [outbound_messages,null,"text"]
    match askmode:
        "json_object":
            body = [outbound_messages,null,"json_object"]
    var url = chat_url
    var json_string = JSON.stringify(body)
    if http_request.get_http_client_status() == HTTPClient.STATUS_REQUESTING:
        await http_request.request_completed
    var err = http_request.request(
        url,
        ["Content-Type: application/json"],
        HTTPClient.METHOD_POST,
        json_string
    )
    if err == ERR_BUSY:
        await http_request.request_completed
        err = http_request.request(
            url,
            ["Content-Type: application/json"],
            HTTPClient.METHOD_POST,
            json_string
        )

func send_image_request():
    # 发送图片生成请求逻辑
    pass
