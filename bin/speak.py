#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = ["voxcpm==2.0.3", "torch==2.14.1", "torchaudio==2.11.0", "transformers==5.20.2"]
# ///
import os, sys
if os.path.isdir(os.path.expanduser("~/.cache/huggingface/hub/models--openbmb--VoxCPM2")):
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("PYTORCH_MPS_HIGH_WATERMARK_RATIO", "0.3")
os.environ.setdefault("PYTORCH_MPS_LOW_WATERMARK_RATIO", "0.2")
import numpy as np, soundfile as sf
from voxcpm import VoxCPM

src, dst, voices = sys.argv[1:4]
paras = [p.strip() for p in open(src).read().split("\n\n") if p.strip()]
if not paras:
    sys.exit(f"{src} is empty")

m = VoxCPM.from_pretrained("openbmb/VoxCPM2", load_denoiser=False)
sr = m.tts_model.sample_rate
voice = f"{voices}/owner.wav"
if not os.path.exists(voice):
    os.makedirs(voices, exist_ok=True)
    sf.write(voice, m.generate(text="(calm, warm male voice, clear, relaxed podcast pace)Merhaba. Bu değişikliği ben yaptım, neden yaptığımı anlatayım.", cfg_value=2.0, inference_timesteps=10), sr)

pause = np.zeros(int(sr * 0.7), dtype=np.float32)
parts = []
for p in paras:
    parts += [m.generate(text=p, reference_wav_path=voice, cfg_value=2.0, inference_timesteps=10), pause]
sf.write(dst, np.concatenate(parts), sr)
