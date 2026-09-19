"""Bounded text-length repair; independent of providers and game state."""
import re
import time


def visible_length(text):
    return len(re.sub(r"\s", "", re.sub(r"<[^>]*>", "", text or "")))


def ensure_minimum_text(messages, text, minimum, generate, deadline):
    """One text-only rewrite. Keep original action tags and never execute tools."""
    minimum = max(0, min(2000, int(minimum)))
    count = visible_length(text)
    status = {"minimum": minimum, "actual": count, "retried": False}
    if not minimum or count >= minimum or not count:
        status["met"] = not minimum or count >= minimum
        return text, status
    remaining = deadline - time.monotonic()
    if remaining < 2:
        status.update(met=False, reason="timeout_budget")
        return text, status
    tags = re.findall(r"<[^>]*>", text)
    repair_messages = list(messages) + [
        {"role": "assistant", "content": re.sub(r"<[^>]*>", "", text)},
        {"role": "user", "content": (
            f"上一版正文只有{count}个非空白字符，要求至少{minimum}个。请输出完整修订版，"
            "保留已有事实、角色立场、拒绝和互动结果；只充分解释已有内容，"
            "不得创造新事件、交易、物品变化或玩家决定，不用重复句填充。"
            "只输出正文，不输出工具调用或尖括号标签。若无法合理扩写，保留原意。"
        )},
    ]
    status["retried"] = True
    try:
        candidate = re.sub(r"<[^>]*>", "", generate(repair_messages, remaining) or "").strip()
        if visible_length(candidate) > count:
            text = candidate + ("\n" + "\n".join(tags) if tags else "")
    except Exception:
        status["reason"] = "repair_failed"
    status.update(actual=visible_length(text), met=visible_length(text) >= minimum)
    return text, status
