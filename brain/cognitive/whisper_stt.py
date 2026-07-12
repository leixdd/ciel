"""Whisper speech-to-text. Future siblings: tts.py, llm/."""
import mlx_whisper
import numpy as np

from memory.store import CFG

MODEL = CFG["model"]


def warm():
    mlx_whisper.transcribe(np.zeros(16000, np.float32), path_or_hf_repo=MODEL)


def transcribe(audio):
    return mlx_whisper.transcribe(audio, path_or_hf_repo=MODEL)["text"].strip()
