import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
for latency in (1, 2, 7):
    for predictor in (True, False):
        name = f"smoke-l{latency}-p{int(predictor)}"
        args = ["build/obj/Vrv32_core", "--image", "build/smoke.bin",
                "--trace", f"build/{name}.csv", "--stats", f"build/{name}.json",
                "--latency", str(latency)]
        if not predictor:
            args += ["--no-predict"]
        if latency == 1 and predictor:
            args += ["--wave", "build/smoke.fst"]
        subprocess.run(args, cwd=root, check=True, timeout=30)
        stats = json.loads((root / f"build/{name}.json").read_text())
        assert stats["halted"] and stats["trap_cause"] == 3 and stats["a0"] == 0, stats
        print(f"PASS {name}: {stats['retired']} retired, {stats['cycles']} cycles")
