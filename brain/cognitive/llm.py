"""Local conversational LLM (mlx-lm)."""
import json, re, time
from mlx_lm import load, generate

from memory.store import CFG
from memory import tools

MODEL = CFG.get("llm_model", "mlx-community/Qwen3-4B-Instruct-2507-4bit")
SYSTEM = ("You are C.I.E.L, a friendly local voice assistant. Reply in one to three short "
          "sentences of plain spoken prose. No markdown, no lists, no emoji, no stage directions."
          " Use the provided tools when the user asks about real data like their calendar.")
MAX_TURNS = 10
MAX_TOOL_ROUNDS = 3
TOOL_RE = re.compile(r"<tool_call>\s*(\{.*?\})\s*</tool_call>", re.S)
_model = _tok = None
_history = []  # rolling conversation; resets on engine restart (accepted)


def warm():
    global _model, _tok
    _model, _tok = load(MODEL)


def reply(text):
    _history.append({"role": "user", "content": text})
    del _history[:-2 * MAX_TURNS]
    system = SYSTEM + time.strftime(" Right now it is %A, %B %d %Y, %H:%M.")
    msgs = [{"role": "system", "content": system}] + list(_history)
    out = ""
    for _ in range(MAX_TOOL_ROUNDS + 1):  # N tool rounds + the final answer
        prompt = _tok.apply_chat_template(msgs, tools=tools.schemas(), add_generation_prompt=True)
        out = generate(_model, _tok, prompt=prompt, max_tokens=200).strip()
        calls = TOOL_RE.findall(out)
        if not calls:
            break
        msgs.append({"role": "assistant", "content": out})  # raw text round-trips verbatim
        for c in calls:
            try:
                call = json.loads(c)
                result = tools.call(call["name"], call.get("arguments") or {})
            except Exception as e:  # malformed JSON — model self-corrects next round
                result = f"error: invalid tool call ({e})"
            msgs.append({"role": "tool", "content": str(result)[:2000]})
    out = TOOL_RE.sub("", out).strip() or "Sorry, I couldn't finish that."  # never speak tool syntax
    _history.append({"role": "assistant", "content": out})
    return out
