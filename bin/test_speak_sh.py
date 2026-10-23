"""Self-check: python3 bin/test_speak_sh.py"""
import os, shutil, subprocess, tempfile, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
FAKE = '#!/usr/bin/env bash\nsleep ${SLEEP:-0}; say --file-format=WAVE --data-format=LEI16@22050 -o "$2" -f "$1"\n'


def setup():
    t = Path(tempfile.mkdtemp())
    (t / "bin").mkdir()
    shutil.copy(HERE / "speak.sh", t / "bin")
    (t / "bin" / "speak.py").write_text(FAKE)
    (t / "bin" / "speak.py").chmod(0o755)
    for r, text in (("r1", "Merhaba."), ("r2", "Selam.")):
        (t / r).mkdir()
        (t / r / "story.tr.md").write_text(text)
    return t


def speak(t, r, sleep=0, wait=True):
    env = {**os.environ, "TASTE_DIR": str(t), "SLEEP": str(sleep)}
    p = subprocess.Popen([str(t / "bin" / "speak.sh"), str(t / r)], env=env)
    return p.wait() if wait else p


def state(t, r):
    v = t / r / "story.voice"
    return v.read_text().strip() if v.exists() else "", (t / r / "story.m4a").exists(), [f for f in os.listdir(t / r) if f.startswith(".story")]


def test_normal_run():
    t = setup()
    speak(t, "r1")
    assert state(t, "r1") == ("VoxCPM2", True, [])
    assert not (t / "lock-speak").exists()


def test_second_job_is_busy():
    t = setup()
    first = speak(t, "r1", sleep=3, wait=False)
    time.sleep(1)
    assert speak(t, "r2") == 1
    assert state(t, "r2")[:2] == ("busy: another story is being spoken, press again later", False)
    first.wait()
    assert state(t, "r1") == ("VoxCPM2", True, [])


def test_story_changed_mid_run_writes_nothing():
    t = setup()
    p = speak(t, "r1", sleep=3, wait=False)
    time.sleep(1)
    (t / "r1" / "story.tr.md").write_text("Yeni hikaye.")
    p.wait()
    assert state(t, "r1") == ("", False, [])


def test_stale_lock_is_taken():
    t = setup()
    (t / "lock-speak").mkdir()
    (t / "lock-speak" / "pid").write_text("999999")
    speak(t, "r2")
    assert state(t, "r2") == ("VoxCPM2", True, [])


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
