"""Kokoro TTS via mlx-audio; plays through default output with sounddevice."""
import re
import numpy as np
import sounddevice as sd

from memory.store import CFG

MODEL = CFG.get("tts_model", "mlx-community/Kokoro-82M-bf16")
VOICE = CFG.get("tts_voice", "af_heart")
OUTPUT = CFG.get("output_device")  # None = system default
_model = None
_models = {}  # model_id -> loaded model, cached for the TTS playground

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


def warm():
    global _model
    _model = _get(MODEL)
    for _ in _segments(_model, "hi", VOICE, "a"):  # silent warm: g2p + voice/speaker pack
        pass


def say(text):
    if not text:
        return
    audio = list(_segments(_model, text, VOICE, "a"))
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


def speak(text, lang="a", voice=None, model=None, on_play=None, should_stop=None):
    """TTS playground: synthesize `text` with `model` (Kokoro or Qwen3-TTS) and play it. `on_play` fires
    right before audio starts; `should_stop()` aborts generation between segments; stop() cuts playback."""
    if not text:
        return
    m = _get(model or MODEL)
    audio = []
    for seg in _segments(m, text, voice, lang):
        if should_stop and should_stop():
            return
        audio.append(seg)
    if not audio or (should_stop and should_stop()):
        return
    if on_play:
        on_play()
    sd.play(np.concatenate(audio), 24000, device=OUTPUT)
    sd.wait()
