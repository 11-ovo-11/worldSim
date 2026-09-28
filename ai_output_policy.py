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
        "抱歉，我不能", "抱歉，无法",
    )
    return any(marker in value for marker in markers)


def ensure_minimum_text(messages, text, minimum, generate, deadline):
    """One text-only rewrite. Keep original action tags and never execute tools."""
    minimum = max(0, min(2000, int(minimum)))
    count = visible_length(text)
    status = {"minimum": minimum, "actual": count, "retried": False}
    refusal_recovery = looks_like_meta_refusal(text)
    # A short but complete scene is preferable to a second pass that turns
    # specific dialogue into an event summary. Retry only severe truncation.
    if not refusal_recovery and (not minimum or count >= minimum or not count or count >= minimum * 0.65):
        status["met"] = not minimum or count >= minimum
        if minimum and count < minimum and count:
            status["reason"] = "preserved_original"
        return text, status
    remaining = deadline - time.monotonic()
    if remaining < 2:
        status.update(met=False, reason="timeout_budget")
        return text, status
    tags = re.findall(r"<[^>]*>", text)
    repair_messages = list(messages) + [
        {"role": "assistant", "content": re.sub(r"<[^>]*>", "", text)},
        {"role": "user", "content": (
            (f"上一版正文只有{count}个非空白字符，要求至少{minimum}个。" if not refusal_recovery else "上一版偏离了角色并出现了元话语。")
            + "请在虚构游戏语境中输出自然的角色内修订版，保留已有事实、角色立场、拒绝和互动结果；"
            "若细节需要收束，使用简短非露骨概述继续场景，不评论政策或安全规则，不返回空内容。"
            "不得创造新事件、交易、物品变化或玩家决定，不用重复句填充。只输出正文，不输出工具调用或尖括号标签。"
        )},
    ]
    status["retried"] = True
    try:
        candidate = re.sub(r"<[^>]*>", "", generate(repair_messages, remaining) or "").strip()
        if candidate and (refusal_recovery or visible_length(candidate) > count):
            text = candidate + ("\n" + "\n".join(tags) if tags else "")
    except Exception:
        status["reason"] = "repair_failed"
    status.update(actual=visible_length(text), met=visible_length(text) >= minimum)
    return text, status
