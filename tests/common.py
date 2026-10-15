"""Build generated bare-metal tests and compare the actual RTL retirement stream."""
from pathlib import Path
import csv
import json
import subprocess
from spike_reference import ROOT, compare, reference, symbol

BUILD = ROOT / "build"
BASE = 0x80000000
RAM_SIZE = 0x100000


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, cwd=ROOT, **kwargs)


def compile_asm(name, body, terminal="ebreak", tail="", definitions="", absolute_end=None):
    source = BUILD / (name + ".S")
    source.write_text(".option norvc\n.option norelax\n.section .text.init\n"
                      ".globl _start,test_end\n_start:\n" + body +
                      ("\ntest_end:\n" if absolute_end is None else f"\n.set test_end,0x{absolute_end:x}\n")
                      + terminal + "\n" + tail + "\n" + definitions)
    return compile_sources(name, [source])


def compile_sources(name, sources, defines=(), linker=None):
    elf = BUILD / (name + ".elf")
    run(["riscv64-unknown-elf-gcc", "-march=rv32im", "-mabi=ilp32", "-mno-relax",
         "-msmall-data-limit=0", "-O2", "-fno-builtin", "-ffreestanding",
         "-nostdlib", "-nostartfiles", "-Wl,--no-relax",
         "-T", linker or ROOT/"tests/programs/link.ld", *defines, *sources, "-o", elf],
        capture_output=True, text=True)
    run(["riscv64-unknown-elf-objcopy", "-O", "binary", elf, elf.with_suffix(".bin")])
    return elf


def records(path):
    with path.open() as f:
        return [{k:int(v,10 if k=="cycle" else 16) for k,v in r.items()}
                for r in csv.DictReader(f)]


def check_memory(binary, expected, dump):
    """Replay only Spike's architectural stores, then compare all 1 MiB.

    The test must FENCE after its last RAM store, or use an uncached run.
    Neither the CPU's store trace nor final register values supply the oracle.
    """
    memory = bytearray(RAM_SIZE)
    image = binary.read_bytes()
    memory[:len(image)] = image
    for r in expected:
        for addr, value in r["stores"]:
            size = {0:1,1:2,2:4}[(r["insn"] >> 12) & 7]
            if BASE <= addr < BASE+RAM_SIZE:
                memory[addr-BASE:addr-BASE+size] = (value & ((1 << (8*size))-1)).to_bytes(size,"little")
    actual = dump.read_bytes()
    if actual != memory:
        bad = next(i for i,(a,b) in enumerate(zip(actual,memory)) if a!=b)
        raise AssertionError(f"{dump.name}: physical RAM mismatch at {BASE+bad:08x}: "
                             f"RTL {actual[bad]:02x}, Spike {memory[bad]:02x}")


def simulate(elf, suffix, expected, terminal, *, latency=1, jitter=0, seed=1,
             cache=True, predictor=True, simd=True, cause=3, tval=0,
             memory=True, options=()):
    stem = elf.stem + "-" + suffix
    trace, stats, dump = [BUILD / (stem+ext) for ext in (".csv",".json",".ram")]
    executable = BUILD / ("obj" if simd else "obj-nosimd") / "Vrv32_system"
    args = [executable, "--image", elf.with_suffix(".bin"), "--trace", trace,
            "--stats", stats, "--dump", dump, "--latency", latency,
            "--jitter", jitter, "--seed", seed, "--limit", 3000000]
    if not cache: args += ["--no-cache"]
    if not predictor: args += ["--no-predict"]
    run([*args,*options], capture_output=True, text=True, timeout=45)
    result = json.loads(stats.read_text())
    assert result["halted"] and result["trap_cause"]==cause and result["trap_tval"]==tval, (stem,result)
    n = compare(trace,expected,terminal)
    assert n == result["retired"], (stem,n,result)
    if memory: check_memory(elf.with_suffix(".bin"),expected,dump)
    # Keep traces and JSON, not a megabyte per successful run.
    dump.unlink()
    return dict(name=stem, **result)


def mnemonic(insn):
    op,f3,f7=insn&127,(insn>>12)&7,insn>>25
    if op==0x33:
        if f7==1: return ["mul","mulh","mulhsu","mulhu","div","divu","rem","remu"][f3]
        if f3==0: return "sub" if f7==32 else "add"
        if f3==5: return "sra" if f7==32 else "srl"
        return {1:"sll",2:"slt",3:"sltu",4:"xor",6:"or",7:"and"}[f3]
    if op==0x13:
        if f3==5: return "srai" if f7==32 else "srli"
        return {0:"addi",1:"slli",2:"slti",3:"sltiu",4:"xori",6:"ori",7:"andi"}[f3]
    if op==0x63: return {0:"beq",1:"bne",4:"blt",5:"bge",6:"bltu",7:"bgeu"}[f3]
    if op==3: return {0:"lb",1:"lh",2:"lw",4:"lbu",5:"lhu"}[f3]
    if op==0x23: return {0:"sb",1:"sh",2:"sw"}[f3]
    if op==0xb: return {0:"xadd8",1:"xadd16",2:"xdot8"}[f3]
    return {0x37:"lui",0x17:"auipc",0x6f:"jal",0x67:"jalr",0xf:"fence"}.get(op,f"unknown-{op:x}")
