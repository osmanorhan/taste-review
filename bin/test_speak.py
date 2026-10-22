"""Self-check: uv run --no-project --with numpy --with soundfile python bin/test_speak.py"""
import json, os, subprocess, sys, tempfile
import numpy as np, soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
STUB = '''import json, os
import numpy as np


class _Tts:
    sample_rate = 100


class VoxCPM:
    tts_model = _Tts()

    @classmethod
    def from_pretrained(cls, *a, **k):
        return cls()

    def generate(self, text, reference_wav_path=None, **k):
        with open(os.environ["STUB_LOG"], "a") as f:
            f.write(json.dumps({"text": text, "ref": reference_wav_path}) + "\\n")
        return np.full(len(text) + 1, {"A": 0.5, "B": 0.25}.get(text, 0.125), dtype=np.float32)
'''


def run(story, voices=None):
    d = tempfile.mkdtemp()
    open(os.path.join(d, "voxcpm.py"), "w").write(STUB)
    src, dst, log = (os.path.join(d, n) for n in ("story.tr.md", "out.wav", "log"))
    voices = voices or os.path.join(d, "voices")
    open(src, "w").write(story)
    env = {**os.environ, "PYTHONPATH": d, "STUB_LOG": log}
    p = subprocess.run([sys.executable, os.path.join(HERE, "speak.py"), src, dst, voices], capture_output=True, text=True, env=env)
    calls = [json.loads(l) for l in open(log)] if os.path.exists(log) else []
    return p, dst, voices, calls


def test_empty_story():
    p, dst, _, _ = run("\n\n  \n\n")
    assert p.returncode != 0
    assert "is empty" in p.stderr, p.stderr
    assert not os.path.exists(dst)


def test_paragraphs_with_pauses():
    p, dst, voices, calls = run("A\n\nB\n")
    assert p.returncode == 0, p.stderr
    audio, sr = sf.read(dst, dtype="float32")
    pause = np.zeros(70, dtype=np.float32)
    want = np.concatenate([np.full(2, 0.5), pause, np.full(2, 0.25), pause]).astype(np.float32)
    assert sr == 100
    assert np.array_equal(audio, want), audio
    assert [c for c in calls if c["text"] in ("A", "B")] == [
        {"text": "A", "ref": f"{voices}/owner.wav"},
        {"text": "B", "ref": f"{voices}/owner.wav"},
    ]


def test_designs_missing_voice():
    p, _, voices, calls = run("A\n")
    assert p.returncode == 0, p.stderr
    assert os.path.isfile(os.path.join(voices, "owner.wav"))
    assert calls[0]["ref"] is None and calls[0]["text"].startswith("(calm, warm male voice"), calls[0]


def test_keeps_existing_voice():
    voices = tempfile.mkdtemp()
    owner = os.path.join(voices, "owner.wav")
    sf.write(owner, np.full(5, 0.5, dtype=np.float32), 100)
    before = open(owner, "rb").read()
    p, _, _, calls = run("A\n", voices)
    assert p.returncode == 0, p.stderr
    assert open(owner, "rb").read() == before
    assert all(c["ref"] == owner for c in calls), calls


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
