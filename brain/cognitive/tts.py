"""Kokoro TTS via mlx-audio; plays through default output with sounddevice."""
import os
import re
import time
import numpy as np
import sounddevice as sd

from memory import store
from memory.store import CFG

FISH_MODEL = "novita/fish-audio-s2-pro"  # cloud TTS (Novita) — not a local mlx model
AUDIO_DIR = os.path.join(os.path.dirname(os.path.abspath(store.__file__)), "audios")
TTS_LOG = os.path.join(AUDIO_DIR, "history.jsonl")  # playground clips: one JSON record per line
MODEL = CFG.get("tts_model", "mlx-community/Kokoro-82M-bf16")
VOICE = CFG.get("tts_voice", "af_heart")
OUTPUT = CFG.get("output_device")  # None = system default
_models = {}  # model_id -> loaded model, cached (warm/say/playground share the cache)

# One default voice per Kokoro language code (voice prefix must match the lang code).
DEFAULT_VOICE = {"a": "af_heart", "b": "bf_emma", "e": "ef_dora", "f": "ff_siwis",
                 "h": "hf_alpha", "i": "if_sara", "p": "pf_dora", "j": "jf_alpha", "z": "zf_xiaobei"}


def _chunk_text(text, budget=200):
    """Split into <=budget-char pieces on line/sentence boundaries. Kokoro truncates past ~510 phonemes
    per generation and only auto-chunks English, so we pre-split for every language."""
    out = []
    for line in text.replace("\r", "").split("\n"):
        for sent in re.findall(r"[^.!?。！？]*[.!?。！？]+|[^.!?。！？]+", line):
            sent = sent.strip()
            while len(sent) > budget:  # over-long run: cut at the last space before the budget
                cut = sent.rfind(" ", 0, budget)
                cut = cut if cut > 0 else budget
                out.append(sent[:cut].strip()); sent = sent[cut:].strip()
            if sent:
                out.append(sent)
    return out


def _get(model):
    m = _models.get(model)
    if m is None:
        try:  # silence transformers' benign "model of type `qwen3_tts`" load warning
            from transformers.utils import logging as hf_logging
            hf_logging.set_verbosity_error()
        except Exception:
            pass
        from mlx_audio.tts.utils import load_model  # heavy import kept out of module top
        m = _models[model] = load_model(model)
    return m


def _is_qwen(m):
    return "qwen3_tts" in type(m).__module__


def _segments(m, text, voice, lang):
    """Yield audio arrays for `text` one generation-segment at a time, engine-aware. Kokoro: per-language
    voice + phoneme chunking. Qwen3-TTS: `voice` is a speaker name, `lang` a language name (or 'auto')."""
    if _is_qwen(m):
        spk = getattr(m, "supported_speakers", []) or []
        v = voice if voice in spk else (spk[0] if spk else None)
        langs = getattr(m, "supported_languages", [])
        lc = lang if lang in langs else "auto"
        for r in m.generate(text=text, voice=v, lang_code=lc):
            yield np.asarray(r.audio)
        return
    if lang == "j":
        _ensure_ja()
    v = voice or DEFAULT_VOICE.get(lang, VOICE)
    for chunk in _chunk_text(text):
        for r in m.generate(text=chunk, voice=v, speed=1.0, lang_code=lang):
            yield np.asarray(r.audio)


def stop():
    sd.stop()  # interrupts any in-progress playback (sd.wait returns)


def _wav_to_pcm(raw):
    """Decode WAV bytes -> (int16 samples[, channels], sample_rate)."""
    import io, wave
    with wave.open(io.BytesIO(raw)) as w:
        ch, sr = w.getnchannels(), w.getframerate()
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    return (pcm.reshape(-1, ch) if ch > 1 else pcm), sr


def _to_pcm16(arr):
    """Float [-1,1] (mlx models) -> int16; passthrough if already int16."""
    arr = np.asarray(arr)
    return arr if arr.dtype == np.int16 else (np.clip(arr, -1, 1) * 32767).astype(np.int16)


def _save_clip(pcm, sr, text, model, voice, lang, raw=None):
    """Write the synthesized audio as a WAV in AUDIO_DIR, append a history line, return the record.
    ponytail: clips accumulate; personal tool, prune the folder by hand if it grows."""
    import json, wave
    os.makedirs(AUDIO_DIR, exist_ok=True)
    name = time.strftime("%Y%m%d-%H%M%S-") + f"{int(time.time() * 1000) % 1000:03d}.wav"
    path = os.path.join(AUDIO_DIR, name)
    if raw is not None:
        with open(path, "wb") as f:
            f.write(raw)
    else:
        with wave.open(path, "wb") as w:
            w.setnchannels(1 if pcm.ndim == 1 else pcm.shape[1])
            w.setsampwidth(2); w.setframerate(sr)
            w.writeframes(pcm.tobytes())
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "text": text,
           "model": model, "voice": voice or "", "lang": lang, "file": path}
    with open(TTS_LOG, "a") as f:
        f.write(json.dumps(rec) + "\n")
    return rec


def _fish_bytes(text, voice, temperature=None, speed=None, volume=None):
    """Fetch WAV bytes from Novita Fish Audio S2 Pro. Reads the API key fresh from config.json.
    temperature = expressiveness [0,1]; speed = prosody multiplier; volume = prosody offset."""
    import json, urllib.request
    key = ""
    if store.CFG_PATH:
        try:
            key = (json.load(open(store.CFG_PATH)).get("novita_api_key") or "").strip()
        except Exception:
            pass
    if not key:
        raise RuntimeError("Set the Novita API key in Settings to use Fish Audio S2 Pro.")
    body = {"text": text, "format": "wav"}
    if voice:
        body["reference_id"] = voice
    if temperature is not None:
        body["temperature"] = temperature
    prosody = {k: v for k, v in (("speed", speed), ("volume", volume)) if v is not None}
    if prosody:
        body["prosody"] = prosody
    req = urllib.request.Request(
        "https://api.novita.ai/v3/fish-audio-s2-pro-text-to-speech",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                 "User-Agent": "CIEL/1.0"})  # Cloudflare 1010-blocks the default Python-urllib UA
    return urllib.request.urlopen(req, timeout=60).read()


def _fish(text, voice, on_play):  # chat/dictation: fetch + play, no saved history
    pcm, sr = _wav_to_pcm(_fish_bytes(text, voice))
    if on_play:
        on_play()
    sd.play(pcm, sr, device=OUTPUT)
    sd.wait()


def play_file(path):
    """Replay a saved WAV clip through the current output device."""
    with open(path, "rb") as f:
        pcm, sr = _wav_to_pcm(f.read())
    sd.play(pcm, sr, device=OUTPUT)
    sd.wait()


def warm():
    if MODEL == FISH_MODEL:  # cloud; nothing to load locally
        return
    for _ in _segments(_get(MODEL), "hi", VOICE, "a"):  # silent warm: g2p + voice/speaker pack
        pass


def say(text):
    if not text:
        return
    if MODEL == FISH_MODEL:
        _fish(text, None, None)  # global chat/dictation voice via Fish default speaker
        return
    audio = list(_segments(_get(MODEL), text, VOICE, "a"))
    if audio:
        sd.play(np.concatenate(audio), 24000, device=OUTPUT)
        sd.wait()


_ja_patched = False


def _ensure_ja():
    """Kokoro builds misaki JAG2P() with the cutlet backend, which needs the ~1GB full unidic dict.
    Switch its default to pyopenjtalk (bundled dict) so Japanese works without that download."""
    global _ja_patched
    if _ja_patched:
        return
    import misaki.ja as mja
    _init = mja.JAG2P.__init__
    mja.JAG2P.__init__ = lambda self, version="pyopenjtalk", unk="❓": _init(self, version=version, unk=unk)
    _ja_patched = True


def speak(text, lang="a", voice=None, model=None, on_play=None, should_stop=None,
          temperature=None, speed=None, volume=None):
    """TTS playground: synthesize `text` with `model`, save a WAV clip to history, play it, return the
    record. `on_play` fires before audio starts; `should_stop()` aborts before playback; stop() cuts it.
    temperature/speed/volume tune Fish Audio voices (ignored by local mlx models)."""
    if not text:
        return None
    model = model or MODEL
    if model == FISH_MODEL:
        if should_stop and should_stop():
            return None
        raw = _fish_bytes(text, voice or None, temperature, speed, volume)
        pcm, sr = _wav_to_pcm(raw)
        rec = _save_clip(pcm, sr, text, model, voice, lang, raw=raw)
    else:
        audio = []
        for seg in _segments(_get(model), text, voice, lang):
            if should_stop and should_stop():
                return None
            audio.append(seg)
        if not audio:
            return None
        pcm, sr = _to_pcm16(np.concatenate(audio)), 24000
        rec = _save_clip(pcm, sr, text, model, voice, lang)
    if should_stop and should_stop():
        return rec  # already saved; skip playback
    if on_play:
        on_play()
    sd.play(pcm, sr, device=OUTPUT)
    sd.wait()
    return rec


if __name__ == "__main__":  # self-check: WAV + float->int16 round-trips, save/replay
    import io, wave
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
        w.writeframes(np.arange(100, dtype=np.int16).tobytes())
    pcm, sr = _wav_to_pcm(buf.getvalue())
    assert sr == 16000 and pcm.shape == (100,) and pcm[7] == 7, (sr, pcm.shape)
    assert _to_pcm16(np.array([-1.0, 0.0, 1.0])).tolist() == [-32767, 0, 32767]
    rec = _save_clip(_to_pcm16(np.zeros(50, np.float32)), 24000, "hi", "m", "v", "a")
    assert os.path.exists(rec["file"]) and rec["text"] == "hi"
    p2, s2 = _wav_to_pcm(open(rec["file"], "rb").read())
    assert s2 == 24000 and p2.shape == (50,), (s2, p2.shape)
    os.remove(rec["file"])
    print("ok")
