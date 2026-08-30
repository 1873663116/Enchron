import json, subprocess, tempfile
from pathlib import Path

HOOK = ".claude/hooks/loop_wakeup_gate.py"

def transcript(records):
    handle = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
    for record in records:
        handle.write(json.dumps(record) + "\n")
    handle.close()
    return handle.name

def user(text="go"):
    return {"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": text}]}}

def assistant(*blocks):
    return {"type": "assistant", "message": {"role": "assistant", "content": list(blocks)}}

def wakeup(**kwargs):
    return {"type": "tool_use", "name": "ScheduleWakeup", "input": kwargs}

def other():
    return {"type": "tool_use", "name": "Bash", "input": {"command": "ls"}}

def run(records, cwd="."):
    payload = json.dumps({"transcript_path": transcript(records), "cwd": cwd})
    done = subprocess.run(["python3", HOOK], input=payload, capture_output=True, text=True)
    return done.returncode, done.stderr.strip()

cases = [
    ("从未用过 loop 的会话不拦", [user(), assistant(other())], 0),
    ("本轮武装了 wakeup 就放行",
     [user(), assistant(wakeup(delaySeconds=900)), user(), assistant(wakeup(delaySeconds=900))], 0),
    ("本轮只干活没武装就拦下",
     [user(), assistant(wakeup(delaySeconds=900)), user(), assistant(other())], 2),
    ("显式 stop:true 结束循环放行",
     [user(), assistant(wakeup(delaySeconds=900)), user(), assistant(wakeup(stop=True))], 0),
    ("上一轮武装过不算数，本轮仍需武装",
     [user(), assistant(wakeup(delaySeconds=900)), user(), assistant(other()), assistant(other())], 2),
]
for name, records, expected in cases:
    code, message = run(records)
    mark = "OK  " if code == expected else "FAIL"
    print(f"{mark} {name}: 期望 {expected} 实得 {code}")
    if code != expected and message:
        print("     ", message[:120])

Path(".claude/loop-off").write_text("")
code, _ = run([user(), assistant(wakeup(delaySeconds=900)), user(), assistant(other())])
print(("OK  " if code == 0 else "FAIL") + f" loop-off 开关生效: 期望 0 实得 {code}")
Path(".claude/loop-off").unlink()

payload = json.dumps({"transcript_path": transcript([user(), assistant(wakeup(delaySeconds=1)), user(), assistant(other())]),
                      "cwd": ".", "stop_hook_active": True})
done = subprocess.run(["python3", HOOK], input=payload, capture_output=True, text=True)
print(("OK  " if done.returncode == 0 else "FAIL") + f" stop_hook_active 防死循环: 期望 0 实得 {done.returncode}")
