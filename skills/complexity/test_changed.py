"""Self-check: python3 test_changed.py"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
d = tempfile.mkdtemp()
git = lambda *a: subprocess.run(["git", "-C", d, *a], check=True, capture_output=True)
src = "def a():\n    return 1\n\n\nclass K:\n    def b(self):\n        return 2\n"
open(os.path.join(d, "m.py"), "w").write(src)
git("init", "-q"); git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qam", "x", "--allow-empty")
git("add", "."); git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "base"); git("branch", "base")
open(os.path.join(d, "m.py"), "w").write(src.replace("return 2", "return 3"))
git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qam", "change")

run = lambda args, stdin="": subprocess.run([sys.executable, os.path.join(HERE, "changed.py"), *args],
                                            input=stdin, capture_output=True, text=True, cwd=d).stdout

rows = '1,1,5,0,2,"a@1-2@m.py","m.py","a","a( )",1,2\n1,1,5,0,2,"b@6-7@m.py","m.py","b","b( self )",6,7\n'
out = run(["csv", "base"], rows)
assert "b@6-7" in out and "a@1-2" not in out, out

j = os.path.join(d, "c.json")
json.dump([{"complexity": 20, "path": "m.py", "function_name": "a"},
           {"complexity": 20, "path": "m.py", "function_name": "K::b"}], open(j, "w"))
out = run(["cog", "base", "15", j])
assert "K::b — COG 20" in out and " a " not in out, out
print("ok")
