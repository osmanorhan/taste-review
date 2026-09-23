"""Self-check: python3 test_crap.py"""
import os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def run(csv_rows, cov_text, **env):
    d = tempfile.mkdtemp()
    p = os.path.join(d, "cov")
    open(p, "w").write(cov_text)
    return subprocess.run([sys.executable, os.path.join(HERE, "crap.py"), p],
                          input=csv_rows, capture_output=True, text=True,
                          env={**os.environ, **env}).stdout


ROW = '5,4,29,2,5,"f@1-5@a/b.py","a/b.py","f","f( a , b )",1,5\n'

# uncovered: 4^2 * 1 + 4 = 20
out = run(ROW, "SF:a/b.py\nDA:1,0\nDA:3,0\nDA:5,0\nend_of_record\n", CRAP_MAX="10")
assert "CRAP 20 (CCN 4, cov 0%)" in out, out

# fully covered: 4 -> under threshold
out = run(ROW, "SF:a/b.py\nDA:1,1\nDA:3,2\nDA:5,1\nend_of_record\n", CRAP_MAX="10")
assert "none over threshold" in out, out

# path suffix match (absolute path in report)
out = run(ROW, "SF:/build/src/a/b.py\nDA:1,0\nDA:5,0\nend_of_record\n", CRAP_MAX="10")
assert "CRAP 20" in out, out

# file absent from report -> flagged, counted 0%
out = run(ROW, "SF:other.py\nDA:1,1\nend_of_record\n", CRAP_MAX="10")
assert "CRAP 20" in out and "not in coverage report" in out, out

# clover xml, 50% covered: 16*0.125+4 = 6
out = run(ROW, '<coverage><project><file path="a/b.py">'
               '<line num="1" count="1" type="stmt"/><line num="5" count="0" type="stmt"/>'
               '</file></project></coverage>', CRAP_MAX="5")
assert "CRAP 6 (CCN 4, cov 50%)" in out, out

# cobertura xml
out = run(ROW, '<coverage><packages><package><classes><class filename="a/b.py"><lines>'
               '<line number="1" hits="0"/><line number="5" hits="0"/>'
               '</lines></class></classes></package></packages></coverage>', CRAP_MAX="10")
assert "CRAP 20" in out, out

# go coverprofile
out = run('5,4,29,2,5,"f@1-5@a/b.go","a/b.go","f","f()",1,5\n',
          "mode: set\na/b.go:1.1,5.2 3 0\n", CRAP_MAX="10")
assert "CRAP 20" in out, out

# no executable lines in range -> skipped, not scored as 0%
out = run(ROW, "SF:a/b.py\nDA:90,0\nend_of_record\n", CRAP_MAX="1")
assert "none over threshold" in out and "skipped" in out, out

# jacoco: package + sourcefile, ci = covered instructions
JROW = '5,4,29,2,5,"f@1-5@src/main/java/com/x/Foo.java","src/main/java/com/x/Foo.java","f","f()",1,5\n'
J = '<report name="r"><package name="com/x"><sourcefile name="Foo.java"><line nr="1" mi="3" ci="0"/><line nr="3" mi="2" ci="0"/><line nr="5" mi="1" ci="0"/></sourcefile></package></report>'
out = run(JROW, J, CRAP_MAX="10")
assert "CRAP 20 (CCN 4, cov 0%)" in out, out
out = run(JROW, J.replace('ci="0"', 'ci="2"'), CRAP_MAX="10")
assert "none over threshold" in out, out

print("ok")
