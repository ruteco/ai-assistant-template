import sys
import os

os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"

from faster_whisper import WhisperModel

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

audio_path = sys.argv[1]
model_size = sys.argv[2] if len(sys.argv) > 2 else "small"

model = WhisperModel(model_size, device="cpu", compute_type="int8",
                      download_root=os.path.join(SCRIPT_DIR, "models"))
segments, info = model.transcribe(audio_path, beam_size=5)
print("".join(s.text for s in segments))
