"""Microphone capture: hotkey-driven push-to-talk buffer. Future: speaker.py."""
import numpy as np
import sounddevice as sd


def input_devices():
    return list(dict.fromkeys(d["name"] for d in sd.query_devices() if d["max_input_channels"] > 0))


def output_devices():
    return list(dict.fromkeys(d["name"] for d in sd.query_devices() if d["max_output_channels"] > 0))


class Recorder:
    def __init__(self, device=None):
        self.recording = False
        self._stream = None
        self._chunks = []
        self._device = device

    def start(self):
        self.recording = True
        self._chunks = []
        self._stream = sd.InputStream(samplerate=16000, channels=1, dtype="float32", device=self._device,
                                      callback=lambda indata, *a: self._chunks.append(indata.copy()))
        self._stream.start()

    def stop(self):
        """Stop capture; return float32 mono 16 kHz audio, or None if empty/too short."""
        self.recording = False
        self._stream.stop()
        self._stream.close()
        if not self._chunks:
            return None
        audio = np.concatenate(self._chunks).flatten()
        if len(audio) < 16000 * 0.3:  # accidental-tap guard
            return None
        return audio
