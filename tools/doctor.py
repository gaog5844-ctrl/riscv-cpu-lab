"""Report real tool availability; missing required tools make this command fail."""
import json
import shutil
import subprocess
from pathlib import Path

prefix = Path.home() / ".local/opt/riscv-cpu-lab"
commands = {
    "verilator": ["verilator", "--version"],
    "iverilog": ["iverilog", "-V"],
    "gcc": ["g++", "--version"],
    "make": ["make", "--version"],
    "riscv-gcc": ["riscv64-unknown-elf-gcc", "--version"],
    "spike": [str(prefix / "spike/bin/spike"), "--help"],
    "gtkwave": ["gtkwave", "--version"],
}
results = {}
for name, cmd in commands.items():
    found = shutil.which(cmd[0])
    if found:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        lines = (p.stdout + p.stderr).splitlines()
        results[name] = {"path": found, "version": lines[0] if lines else "", "exit": p.returncode}
    else:
        results[name] = {"missing": True}
serialized=json.dumps(results, indent=2, ensure_ascii=False)
build=Path(__file__).resolve().parents[1]/"build"
build.mkdir(exist_ok=True)
(build/"doctor.json").write_text(serialized+"\n")
print(serialized)
raise SystemExit(1 if any(r.get("missing") or r.get("exit", 0) != 0 for r in results.values()) else 0)
