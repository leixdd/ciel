"""Config load, JSON event emission, transcript history (history.jsonl)."""
import json, os, sys, time

DEFAULTS = {"model": "mlx-community/whisper-large-v3-mlx-8bit",
            "hotkey": "alt_r",
            "log_dir": os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")}
CFG = dict(DEFAULTS)
CFG_PATH = None  # path to the live config.json, so secrets can be re-read without a restart
if "--config" in sys.argv:
    CFG_PATH = sys.argv[sys.argv.index("--config") + 1]
    CFG.update(json.load(open(CFG_PATH)))
os.makedirs(CFG["log_dir"], exist_ok=True)
LOG = os.path.join(CFG["log_dir"], "history.jsonl")


def emit(event, **kw):
    line = json.dumps({"event": event, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"), **kw})
    print(line, flush=True)  # flush: piped stdout is block-buffered
    if event in ("transcript", "error"):
        with open(LOG, "a") as f: f.write(line + "\n")
