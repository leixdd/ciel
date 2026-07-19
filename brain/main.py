# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = ["mlx-whisper", "sounddevice", "pynput", "numpy", "mlx-lm", "mlx-audio", "misaki[en,ja]", "pyobjc-framework-EventKit"]
# ///
"""Wispr Flow-style local dictation: hold the hotkey, speak, release, paste."""
import json, subprocess, sys, threading, time
from pynput import keyboard
from pynput.keyboard import Key, Controller

from memory.store import CFG, emit
from memory import tools as brain_tools
from hearing.microphone import Recorder, input_devices, output_devices
from cognitive import whisper_stt

SPEAK = bool(CFG.get("speak_mode"))
if (SPEAK or "--say" in sys.argv) and "--check" not in sys.argv:
    from cognitive import llm, tts

HOTKEY = getattr(Key, CFG["hotkey"])
kb = Controller()
rec = Recorder(CFG.get("input_device"))

_voice_ready = False
_voice_lock = threading.Lock()  # serialize LLM+TTS across dictation and typed chat


def ensure_voice():
    """Lazy-load LLM+TTS the first time voice output is needed (e.g. typed chat with speak_mode off)."""
    global _voice_ready, llm, tts
    if _voice_ready:
        return
    from cognitive import llm, tts
    emit("loading")
    llm.warm(); tts.warm()
    _voice_ready = True


def respond(text):
    """Reply with the LLM, speak it, log a transcript. Shared by typed chat and speak-mode dictation."""
    ensure_voice()
    emit("speaking")
    with _voice_lock:  # ponytail: one voice at a time; concurrent dictation+chat would garble audio
        reply = llm.reply(text)
        tts.say(reply)  # blocks until playback done
    emit("transcript", text=text, reply=reply)


def speak_tts(spec):
    """TTS playground request from the app: {"text","lang","model"} -> synthesize and play."""
    text = (spec.get("text") or "").strip()
    if not text:
        return
    from cognitive import tts  # idempotent; playground needs TTS but not the LLM
    emit("speaking")
    with _voice_lock:
        tts.speak(text, lang=spec.get("lang", "a"), voice=spec.get("voice"), model=spec.get("model"))
    emit("idle")


def chat_loop():
    """Read one JSON object per stdin line from the app; {"chat":...} speaks a reply, {"tts":{...}} plays raw TTS."""
    for line in sys.stdin:
        try:
            msg = json.loads(line)
        except Exception:
            continue
        if not isinstance(msg, dict):
            continue
        try:
            if msg.get("chat"):
                respond(msg["chat"].strip())
            elif msg.get("tts"):
                speak_tts(msg["tts"])
        except Exception as e:
            emit("error", message=str(e))


def transcribe_and_inject(audio):
    try:
        text = whisper_stt.transcribe(audio)
        if not text:
            emit("idle")
            return
        if SPEAK:
            respond(text)
            return
        old = subprocess.run(["pbpaste"], capture_output=True).stdout
        subprocess.run(["pbcopy"], input=text.encode())
        time.sleep(0.1)  # pasteboard settle
        with kb.pressed(Key.cmd):
            kb.tap("v")
        time.sleep(0.3)  # slow apps (browsers) must read clipboard before restore
        # ponytail: text-only clipboard restore; rich content lost. Bump 0.3->0.5s if pastes flake.
        subprocess.run(["pbcopy"], input=old)
        subprocess.Popen(["afplay", "/System/Library/Sounds/Glass.aiff"])
        emit("transcript", text=text)
    except Exception as e:
        emit("error", message=str(e))


def on_press(key):
    if key != HOTKEY or rec.recording:  # guard re-entrant key-repeat presses
        return
    try:
        rec.start()
    except Exception as e:
        emit("error", message=f"mic: {e}")
        return
    emit("recording")
    subprocess.Popen(["afplay", "/System/Library/Sounds/Pop.aiff"])


def on_release(key):
    if key != HOTKEY or not rec.recording:
        return
    audio = rec.stop()
    if audio is None:
        emit("idle")
        return
    emit("transcribing")
    # NEVER transcribe in the pynput callback: blocking the CGEventTap disables the hotkey.
    threading.Thread(target=transcribe_and_inject, args=(audio,), daemon=True).start()


def main():
    if "--check" in sys.argv:
        t = time.time()
        whisper_stt.warm()
        whisper_stt.warm()  # second pass measures warm-model latency
        print(f"OK {time.time() - t:.1f}s")
        return
    if "--say" in sys.argv:
        llm.warm(); tts.warm()
        r = llm.reply(sys.argv[sys.argv.index("--say") + 1])
        print(r)
        tts.say(r)
        return
    emit("loading", model=whisper_stt.MODEL)
    t0 = time.time()
    try:
        whisper_stt.warm()
        if SPEAK:
            global _voice_ready
            llm.warm(); tts.warm()
            _voice_ready = True
    except Exception as e:
        emit("error", message=f"startup: {e}")
        raise
    emit("ready", model=whisper_stt.MODEL, hotkey=CFG["hotkey"], load_secs=round(time.time() - t0, 1), devices=input_devices(), output_devices=output_devices(), tools=brain_tools.listing())
    threading.Thread(target=chat_loop, daemon=True).start()  # typed chat from the app over stdin
    with keyboard.Listener(on_press=on_press, on_release=on_release) as l:
        l.join()


if __name__ == "__main__":
    main()
