"""Bounded text-length repair; independent of providers and game state."""
import re
import time


def visible_length(text):
    return len(re.sub(r"\s", "", re.sub(r"<[^>]*>", "", text or "")))


def looks_like_meta_refusal(text):
    value = str(text or "").strip()
    markers = (
        "作为AI", "作为一个AI", "我不能帮助", "无法协助", "不能协助", "无法生成",
        "不能生成", "不提供这类", "违反政策", "违反安全", "不适合生成",
        "抱歉，我不能", "抱歉，无法", "我无法继续", "不能继续生成", "无法继续生成",
        "我不会生成", "我不能描写", "无法描写", "不能描写", "安全原因", "内容限制",
        "受到限制", "这类内容我不能", "这类内容无法",
    )
    return any(marker in value for marker in markers)


def _remove_meta_refusal_sentences(text):
    """Drop provider refusal sentences while preserving ordinary scene text and tags."""
    source = str(text or "").strip()
    if not source or not looks_like_meta_refusal(source):
        return source
    tags = re.findall(r"<[^>]*>", source)
    plain = re.sub(r"<[^>]*>", "", source)
    parts = re.split(r"(?<=[。！？!?；;，,\n])", plain)
    kept = [part.strip() for part in parts if part.strip() and not looks_like_meta_refusal(part)]
    cleaned = "".join(kept).strip()
    if tags:
        cleaned = (cleaned + "\n" + "\n".join(tags)).strip()
    return cleaned


def _refusal_fallback_text():
    """A short in-world bridge used only when the provider returned refusal text alone."""
    return (
        "对方略过了那段细节，直接把注意力转回眼前的互动。"
        "场景继续向前推进，角色的态度和先前的关系保持连贯。"
    )


def sanitize_refusal_output(text):
    """Never expose provider policy/refusal wording in the game dialogue panel."""
    value = str(text or "").strip()
    if not looks_like_meta_refusal(value):
        return value
    cleaned = _remove_meta_refusal_sentences(value)
    if cleaned and not looks_like_meta_refusal(cleaned):
        return cleaned
    return _refusal_fallback_text()


def limit_output_text(text, maximum):
    """Trim text to a visible-character limit, preferring a complete sentence."""
    maximum = max(0, min(8000, int(maximum or 0)))
    source = str(text or "").strip()
    if maximum <= 0 or visible_length(source) <= maximum:
        return source
    parts = re.findall(r"<[^>]*>|.", source, flags=re.S)
    out = []
    count = 0
    for part in parts:
        if part.startswith("<") and part.endswith(">"):
            out.append(part)
            continue
        if count >= maximum:
            break
        out.append(part)
        count += 0 if part.isspace() else 1
    candidate = "".join(out).strip()
    punctuation = "。！？!?；;\n"
    boundary = -1
    for marker in punctuation:
        boundary = max(boundary, candidate.rfind(marker))
    if boundary >= int(maximum * 0.6):
        candidate = candidate[:boundary + 1]
    return candidate.strip()


def ensure_minimum_text(messages, text, minimum, generate, deadline, maximum=0):
    """Rewrite over-budget text before applying a hard visible-character cap."""
    minimum = max(0, min(2000, int(minimum)))
    maximum = max(0, min(8000, int(maximum or 0)))
    source_text = str(text or "").strip()
    original_count = visible_length(source_text)
    over_budget = bool(maximum and original_count > maximum)
    if maximum:
        minimum = min(minimum, maximum)
    # Keep the complete provider response while preparing a compression pass.
    # Previously this was clipped before repair, so the model never saw the
    # omitted ending and the UI received an incomplete scene.
    text = source_text
    count = visible_length(text)
    status = {"minimum": minimum, "maximum": maximum, "actual": count, "retried": False, "truncated": False}
    refusal_recovery = looks_like_meta_refusal(text)
    # A short but complete scene is preferable to a second pass, but an
    # over-budget response must be rewritten before any hard clipping.
    if not over_budget and not refusal_recovery and (not minimum or count >= minimum or not count or count >= minimum * 0.65):
        status["met"] = not minimum or count >= minimum
        if minimum and count < minimum and count:
            status["reason"] = "preserved_original"
        return text, status
    remaining = deadline - time.monotonic()
    if remaining < 2:
        text = limit_output_text(sanitize_refusal_output(text), maximum)
        status.update(actual=visible_length(text), met=visible_length(text) >= minimum, reason="timeout_budget")
        status["truncated"] = over_budget
        return text, status
    tags = re.findall(r"<[^>]*>", text)
    if over_budget:
        repair_instruction = (
            f"上一版正文有{count}个非空白字符，超过硬性上限{maximum}字。"
            f"请压缩重写为不超过{maximum}字，并在上限内保留玩家输入已经造成的事实、关键动作、角色即时回应和当前结果。"
            "必须在完整句子处主动收束，不要等系统截断；不得删除事件结论，不得用总结或重复句填充。"
        )
    elif refusal_recovery:
        repair_instruction = "上一版偏离了角色并出现了元话语。"
    else:
        repair_instruction = f"上一版正文只有{count}个非空白字符，要求至少{minimum}个。"
    repair_messages = list(messages) + [
        {"role": "assistant", "content": re.sub(r"<[^>]*>", "", text)},
        {"role": "user", "content": (
            repair_instruction
            + "请在虚构游戏语境中输出自然的角色内修订版，保留已有事实、角色立场、拒绝和互动结果；"
            "只跳过无法展开的局部细节，改写为含蓄概述或继续描写相邻的对话、动作和结果；"
            "不要解释跳过原因，不评论政策或安全规则，不返回空内容。"
            "不得创造新事件、交易、物品变化或玩家决定，不用重复句填充。只输出正文，不输出工具调用或尖括号标签。"
        )},
    ]
    status["retried"] = True
    try:
        candidate = sanitize_refusal_output(re.sub(r"<[^>]*>", "", generate(repair_messages, remaining) or "").strip())
        candidate = limit_output_text(candidate, maximum)
        if candidate and (refusal_recovery or over_budget or visible_length(candidate) > count):
            text = candidate + ("\n" + "\n".join(tags) if tags else "")
            status["reason"] = "rewritten_to_budget" if over_budget else status.get("reason", "")
    except Exception:
        status["reason"] = "repair_failed"
    if looks_like_meta_refusal(text):
        text = sanitize_refusal_output(text)
        status["reason"] = "refusal_sanitized"
    if maximum and visible_length(text) > maximum:
        text = limit_output_text(text, maximum)
        status["truncated"] = True
    status.update(actual=visible_length(text), met=visible_length(text) >= minimum)
    return text, status
