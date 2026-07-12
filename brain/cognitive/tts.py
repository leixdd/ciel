"""Kokoro TTS via mlx-audio; plays through default output with sounddevice."""
import numpy as np
import sounddevice as sd

from memory.store import CFG

MODEL = CFG.get("tts_model", "mlx-community/Kokoro-82M-bf16")
VOICE = CFG.get("tts_voice", "af_heart")
_model = None


def warm():
    global _model
    from mlx_audio.tts.utils import load_model  # heavy import kept out of module top
    _model = load_model(MODEL)
    list(_model.generate(text="hi", voice=VOICE, speed=1.0, lang_code="a"))  # silent warm: g2p + voice pack


def say(text):
    if not text:
        return
    chunks = [np.asarray(r.audio) for r in _model.generate(text=text, voice=VOICE, speed=1.0, lang_code="a")]
    if not chunks:
        return
    sd.play(np.concatenate(chunks), 24000)
    sd.wait()
