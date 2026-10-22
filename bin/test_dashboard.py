"""Self-check: python3 bin/test_dashboard.py"""
import importlib.util, json, os, tempfile, threading, urllib.error, urllib.request
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
os.environ["TASTE_DIR"] = tempfile.mkdtemp()
spec = importlib.util.spec_from_file_location("dashboard", HERE / "dashboard.py")
dash = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dash)

D1 = dash.TASTE / "reviews" / "o" / "r" / "1"
D2 = dash.TASTE / "reviews" / "o" / "r" / "2"
for d, n in ((D1, 1), (D2, 2)):
    d.mkdir(parents=True)
    (d / "status.json").write_text(json.dumps({"repo": "o/r", "number": n}))

srv = dash.ThreadingHTTPServer(("127.0.0.1", 0), dash.H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
URL = f"http://127.0.0.1:{srv.server_address[1]}"


def proc(code):
    p = mock.Mock()
    p.poll.return_value = code
    return p


def speak(number):
    req = urllib.request.Request(f"{URL}/api/speak", json.dumps({"repo": "o/r", "number": number}).encode(), method="POST")
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def test_speak_without_story_is_404():
    dash.SPEAKING.clear()
    with mock.patch.object(dash.subprocess, "Popen") as popen:
        assert speak(2) == (404, {"ok": False, "err": "no story"})
        popen.assert_not_called()


def test_speak_starts_speak_sh():
    dash.SPEAKING.clear()
    (D1 / "story.tr.md").write_text("Merhaba\n")
    with mock.patch.object(dash.subprocess, "Popen", return_value=proc(None)) as popen:
        assert speak(1) == (200, {"ok": True})
        popen.assert_called_once()
        assert popen.call_args[0][0] == [str(dash.HERE / "speak.sh"), str(D1)]


def test_speak_while_running_does_not_start_again():
    dash.SPEAKING.clear()
    (D1 / "story.tr.md").write_text("Merhaba\n")
    with mock.patch.object(dash.subprocess, "Popen", return_value=proc(None)) as popen:
        speak(1)
        assert speak(1) == (200, {"ok": True})
        assert popen.call_count == 1


def test_speak_after_end_starts_again():
    dash.SPEAKING.clear()
    (D1 / "story.tr.md").write_text("Merhaba\n")
    with mock.patch.object(dash.subprocess, "Popen", side_effect=[proc(0), proc(None)]) as popen:
        speak(1)
        speak(1)
        assert popen.call_count == 2


def test_speaking():
    dash.SPEAKING.clear()
    assert dash.speaking(D1) is False
    dash.SPEAKING[D1] = proc(None)
    assert dash.speaking(D1) is True
    dash.SPEAKING[D1] = proc(1)
    assert dash.speaking(D1) is False


def test_reviews_story_audio_voice():
    dash.SPEAKING.clear()
    (D1 / "story.tr.md").write_text("Bir hikaye\n")
    (D1 / "story.m4a").write_bytes(b"m4a")
    (D1 / "story.voice").write_text("VoxCPM2\n")
    dash.SPEAKING[D1] = proc(None)
    rows = {r["number"]: r for r in dash.reviews()}
    assert rows[1]["story"] == "Bir hikaye\n"
    assert rows[1]["audio"] == "/files/o/r/1/story.m4a"
    assert rows[1]["voice"] == "VoxCPM2"
    assert rows[1]["speaking"] is True
    assert rows[2]["audio"] == "" and rows[2]["voice"] == ""
    assert rows[2]["speaking"] is False


def test_files_m4a_content_type():
    (D1 / "story.m4a").write_bytes(b"m4a")
    with urllib.request.urlopen(f"{URL}/files/o/r/1/story.m4a") as r:
        assert r.headers["Content-Type"] == "audio/mp4", r.headers["Content-Type"]


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
