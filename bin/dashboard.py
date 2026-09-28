#!/usr/bin/env python3
import json, os, subprocess
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

TASTE = Path(os.environ.get("TASTE_DIR", Path.home() / ".taste"))
HERE = Path(__file__).resolve().parent
PORT = int(os.environ.get("TASTE_PORT", 7331))


def targets(d, st):
    if "set" not in st:
        return [(st, d / "comment.md")]
    return [(pr, d / "comments" / pr["repo"] / f"{pr['number']}.md") for pr in st["prs"].values()]


def reviews():
    out = []
    found = [*TASTE.glob("reviews/*/*/*/status.json"), *TASTE.glob("reviews/_sets/*/status.json")]
    for s in sorted(found, key=lambda p: p.stat().st_mtime, reverse=True):
        d = json.loads(s.read_text())
        r = s.parent / "review.md"
        d["review"] = r.read_text() if r.exists() else ""
        d["comments"] = {f"{pr['repo']}#{pr['number']}": c.read_text() for pr, c in targets(s.parent, d) if c.exists()}
        base = f"/files/{s.parent.relative_to(TASTE / 'reviews')}"
        d["png"] = f"{base}/flow.png" if (s.parent / "flow.png").exists() else ""
        d["excalidraw"] = f"{base}/flow.excalidraw" if (s.parent / "flow.excalidraw").exists() else ""
        out.append(d)
    return out


def review_dir(body):
    return TASTE / "reviews" / (f"_sets/{body['set']}" if "set" in body else f"{body['repo']}/{body['number']}")


def save(d, st):
    (d / "status.json").write_text(json.dumps(st, indent=1))


class H(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            return self.send_file(HERE.parent / "dashboard" / "index.html", "text/html")
        if self.path == "/api/list":
            return self.send_json(reviews())
        if self.path.startswith("/api/model/"):
            repo = self.path[11:]
            m = TASTE / "model" / f"{repo}.md"
            log = subprocess.run(["git", "-C", str(TASTE), "log", "--format=%ad %s", "--date=short", "--", f"model/{repo}.md"], capture_output=True, text=True).stdout
            return self.send_json({"repo": repo, "model": m.read_text() if m.exists() else "", "history": log.splitlines()})
        if self.path.startswith("/files/"):
            p = (TASTE / "reviews" / self.path[7:]).resolve()
            if p.is_file() and TASTE.resolve() in p.parents:
                return self.send_file(p, "image/png" if p.suffix == ".png" else "application/octet-stream")
        self.send_error(404)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        d = review_dir(body)
        st = json.loads((d / "status.json").read_text())
        if self.path == "/api/approve":
            urls = []
            for pr, c in targets(d, st):
                if pr.get("posted_url") or not c.exists():
                    continue
                p = subprocess.run(["gh", "pr", "comment", str(pr["number"]), "--repo", pr["repo"], "--body-file", str(c)], capture_output=True, text=True)
                if p.returncode:
                    save(d, st)
                    return self.send_json({"ok": False, "err": p.stderr}, 500)
                pr["posted_url"] = p.stdout.strip()
                urls.append(pr["posted_url"])
            if not urls:
                return self.send_json({"ok": False, "err": "nothing to post"}, 500)
            st["status"] = "posted"
            save(d, st)
            return self.send_json({"ok": True, "url": " ".join(urls)})
        if self.path == "/api/rerun":
            refs = list(st["prs"]) if "set" in st else [f"{st['repo']}#{st['number']}"]
            st["status"] = "queued"
            save(d, st)
            subprocess.Popen([str(HERE / "run.sh"), *refs], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return self.send_json({"ok": True})
        self.send_error(404)

    def send_json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def send_file(self, p, ctype):
        b = p.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print(f"taste dashboard http://127.0.0.1:{PORT}  ({TASTE})", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
