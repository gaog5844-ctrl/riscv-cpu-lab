"""Independent Spike commit stream, bounded by a linked test_end symbol."""
from pathlib import Path
import csv
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SPIKE = Path.home() / ".local/opt/riscv-cpu-lab/spike/bin/spike"


def symbol(elf, name):
    symbols = subprocess.check_output(["riscv64-unknown-elf-nm", str(elf)], text=True)
    for line in symbols.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] == name:
            return int(parts[0], 16)
    raise ValueError(f"missing symbol {name} in {elf}")


def reference(elf, log):
    terminal = symbol(elf, "test_end")
    commands = log.with_suffix(".commands.txt")
    commands.write_text(f"until pc 0 {terminal:x}\npc 0\nreg 0 a0\nq\n")
    args = [str(SPIKE), "--isa=rv32im", "-m0x80000000:0x100000", "--pc=0x80000000",
            "--extlib=" + str(ROOT / "build/xsimd.so"), "--extension=xsimd",
            "--log-commits", "--log=" + str(log), "--debug-cmd=" + str(commands),
            "--instructions=1000000", "-d", str(elf)]
    p = subprocess.run(args, text=True, capture_output=True, timeout=30)
    (log.parent / (log.stem + "-console.txt")).write_text(p.stdout + p.stderr)
    if p.returncode:
        raise AssertionError(f"Spike failed {p.returncode}: {p.stderr[-2000:]}")
    assert re.search(rf"0x(?:0*){terminal:x}\b", p.stdout+p.stderr, re.I), (
        "Spike did not reach test_end", terminal, p.stdout[-500:], p.stderr[-500:])
    lines = log.read_text().splitlines()
    records = []
    for line in lines:
        # Example: core 0: 3 0x80000000 (0x800ff137) x 2 0x800ff000
        m = re.match(r"core\s+\d+:\s+\d+\s+0x([0-9a-f]+)\s+\(0x([0-9a-f]+)\)(.*)", line)
        if not m:
            continue
        pc, insn = int(m[1],16)&0xffffffff, int(m[2],16)
        if not 0x80000000 <= pc < 0x80100000:
            continue
        tail=m[3]
        reg=re.search(r"\bx\s*(\d+)\s+0x([0-9a-f]+)",tail)
        writes=re.findall(r"\bmem\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)",tail)
        records.append(dict(pc=pc,insn=insn,rd=int(reg[1]) if reg else 0,
                            data=(int(reg[2],16)&0xffffffff) if reg and int(reg[1]) else 0,
                            stores=[(int(a,16)&0xffffffff,int(v,16)) for a,v in writes]))
    assert records, "Spike did not produce commit records"
    registers=[0]*32
    for r in records:
        insn=r["insn"]
        if insn&127==3:
            immediate=insn>>20
            if immediate&0x800: immediate-=0x1000
            r["load_addr"]=(registers[(insn>>15)&31]+immediate)&0xffffffff
        if r["rd"]: registers[r["rd"]]=r["data"]
    return records, terminal


def compare(trace_path, expected, terminal):
    with trace_path.open() as f:
        actual = [{k:int(v,10 if k=="cycle" else 16) for k,v in row.items()}
                  for row in csv.DictReader(f)]
    assert actual and actual[-1]["trap"] and actual[-1]["pc"] == terminal, actual[-1:] 
    assert all(actual[-1][key] == 0 for key in ("rd", "data", "mem_wstrb")), (
        trace_path, "faulting retirement has a write", actual[-1])
    normal=actual[:-1]
    assert len(normal)==len(expected), (trace_path, len(normal), len(expected))
    for index,(a,b) in enumerate(zip(normal,expected)):
        assert not a["trap"], (trace_path, index, "unexpected trap in normal prefix", a)
        for key in ("pc","insn","rd","data"):
            assert a[key]==b[key], (trace_path,index,key,a,b)
        next_pc=expected[index+1]["pc"] if index+1<len(expected) else terminal
        assert a["npc"]==next_pc, (trace_path,index,"next_pc",a,next_pc)
        if "load_addr" in b:
            assert a["mem_addr"]==b["load_addr"], (trace_path,index,"load address",a,b)
        if a["mem_wstrb"]:
            assert len(b["stores"])==1, (trace_path,index,"missing Spike store",a,b)
            addr,value=b["stores"][0]
            size={0:1,1:2,2:4}[(a["insn"]>>12)&7]
            expected_strobe=((1<<size)-1)<<(addr&3)
            assert a["mem_wstrb"]==expected_strobe, (trace_path,index,"store byte enable",a,expected_strobe)
            mask=(1<<(8*size))-1
            assert addr==a["mem_addr"], (trace_path,index,"store address",a,b)
            assert ((a["mem_data"]>>(8*(addr&3)))&mask)==(value&mask), (trace_path,index,"store data",a,b)
        else:
            assert not b["stores"], (trace_path,index,"unexpected Spike store",a,b)
    return len(normal)


if __name__=="__main__":
    expected, terminal=reference(ROOT/"build/smoke.elf",ROOT/"build/spike-smoke.log")
    for trace in sorted((ROOT/"build").glob("smoke-l*-p*.csv")):
        n=compare(trace,expected,terminal)
        print(f"PASS Spike differential: {trace.name}: {n} committed instructions")
