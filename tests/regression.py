"""Deterministic instruction/hazard/cache/exception integration tests.

All nonfaulting retirements are checked against pinned Spike + independent Xsimd.
Faulting instructions are checked against this EEI's explicit cause/tval contract.
"""
from collections import Counter
import json
import random
from common import BUILD, compile_asm, mnemonic, reference, simulate, symbol

RR = "add sub sll slt sltu xor srl sra or and mul mulh mulhsu mulhu div divu rem remu".split()
RI = "addi slti sltiu xori ori andi".split()
BR = "beq bne blt bge bltu bgeu".split()
REQUIRED = set(RR+RI+BR+"slli srli srai lui auipc jal jalr lb lh lw lbu lhu sb sh sw fence xadd8 xadd16 xdot8".split())


def directed():
    lines = ["li sp,0x800ff000", "li x28,0x80040000", "li x30,0x10000004"]
    edges = [0,1,0xffffffff,0x80000000,0x7fffffff,2,31,32,0x8080ff01,0x7f00feff]
    for i,a in enumerate(edges):
        for b in edges:
            lines += [f"li x5,0x{a:x}",f"li x6,0x{b:x}"]
            lines += [f"{op} x7,x5,x6" for op in RR]
            lines += [f".insn r 0x0b,{f3},0,x8,x5,x6" for f3 in range(3)]
            # Reuse results immediately: forward M/SIMD into ALU and store data.
            lines += ["add x9,x7,x8",f"sw x9,{i*4}(x28)"]
    for imm in [-2048,-1,0,1,2047]:
        lines += ["li x5,0x80000001"]+[f"{op} x7,x5,{imm}" for op in RI]
    for shift in [0,1,31]:
        lines += [f"{op} x7,x5,{shift}" for op in ["slli","srli","srai"]]
    lines += ["li x5,0x81fe7f80","sw x5,0(x28)","sb x5,5(x28)","sh x5,6(x28)"]
    lines += [f"{op} x7,{off}(x28)" for op,off in [("lb",0),("lbu",0),("lh",2),("lhu",2),("lw",0)]]
    lines += ["lw x7,0(x28)","add x8,x7,x7","sw x8,8(x28)",
              "add x0,x7,x8","addi x9,x0,33","lw x0,0(x28)"]
    for i,op in enumerate(BR):
        for j,(a,b) in enumerate([(1,1),(1,2),(0xffffffff,1)]):
            label=f"branch_{i}_{j}"
            lines += [f"li x5,0x{a:x}",f"li x6,0x{b:x}",f"{op} x5,x6,{label}",
                      "addi x7,x7,1",f"{label}:","addi x8,x7,3"]
    lines += ["li x12,12","loop_flush:","beq x0,x0,no_wrong_store",
              "sw x5,0(x30)","ebreak","no_wrong_store:","addi x12,x12,-1",
              "bne x12,x0,loop_flush",
              "la x5,call_target","ori x5,x5,1","jalr x1,0(x5)",
              "jal x0,after_call",".balign 256","call_target:",
              "addi x6,x0,77","jalr x0,0(x1)","after_call:",
              "li x5,13","li x6,3","lw x7,64(x28)","div x8,x5,x6",
              "add x9,x8,x7","sw x9,68(x28)","fence rw,rw","li a0,0"]
    return "\n".join(lines)


def random_program(seed, count=450):
    rng=random.Random(seed)
    lines=["li sp,0x800ff000","li x28,0x80050000"]
    for r in range(1,28): lines.append(f"li x{r},0x{rng.getrandbits(32):x}")
    for i in range(count):
        rd,a,b=[f"x{rng.randrange(0,28)}" for _ in range(3)]
        kind=rng.randrange(7)
        if kind==0: lines.append(f"{rng.choice(RR)} {rd},{a},{b}")
        elif kind==1: lines.append(f"{rng.choice(RI)} {rd},{a},{rng.randrange(-2048,2048)}")
        elif kind==2: lines.append(f"{rng.choice(['slli','srli','srai'])} {rd},{a},{rng.randrange(32)}")
        elif kind==3:
            op=rng.choice(["sb","sh","sw","lb","lbu","lh","lhu","lw"])
            align=4 if op in ("sw","lw") else 2 if op in ("sh","lh","lhu") else 1
            lines.append(f"{op} {rd},{rng.randrange(0,1024)//align*align}(x28)")
        elif kind==4: lines.append(f".insn r 0x0b,{rng.randrange(3)},0,{rd},{a},{b}")
        elif kind==5:
            lines += [f"{rng.choice(BR)} {a},{b},skip_{i}",f"addi {rd},{rd},1",f"skip_{i}:"]
        else:
            # Load-use, repeated rd writes, then a store with two pending dependencies.
            lines += [f"lw {rd},0(x28)",f"add {rd},{rd},{b}",f"sw {rd},4(x28)"]
    return "\n".join(lines+["fence rw,rw","li a0,0"])


def main():
    BUILD.mkdir(exist_ok=True)
    results=[]
    coverage=Counter()
    def oracle(elf):
        expected,end=reference(elf,BUILD/(elf.stem+"-spike.log"))
        coverage.update(mnemonic(r["insn"]) for r in expected)
        return expected,end
    # Minimized from seed 20261015: iterative division must not capture an old
    # operand while its producing load waits for a cache refill in MEM.
    elf=compile_asm("div-load-hazard","\n".join([
        "li x28,0x80040000","li x6,1","li x17,1184",
        "lw x6,0(x28)","div x15,x17,x6",
        "li x17,123","lw x17,32(x28)","div x16,x17,x6",
        "fence rw,rw","li a0,0"]))
    expected,end=oracle(elf)
    results.append(simulate(elf,"cache-miss",expected,end,latency=3))
    elf=compile_asm("directed",directed())
    expected,end=oracle(elf)
    # Full cache/predictor matrix, deterministic ready backpressure and response jitter.
    for cache in [False,True]:
        for predict in [False,True]:
            for latency,jitter in [(1,0),(3,5)]:
                result=simulate(elf,f"c{int(cache)}p{int(predict)}l{latency}j{jitter}",expected,end,
                                cache=cache,predictor=predict,latency=latency,jitter=jitter,seed=20261015)
                assert result["mmio_writes"]==0,result
                assert result["a0"]==0,result
                results.append(result)
                print(f"PASS {result['name']}: {result['retired']} Spike comparisons",flush=True)
    for seed in [1,7,42,73,101,257,65537,20261015]:
        elf=compile_asm(f"random-{seed}",random_program(seed))
        expected,end=oracle(elf)
        for cache in [False,True]:
            result=simulate(elf,f"c{int(cache)}-jitter",expected,end,cache=cache,
                            latency=2,jitter=7,seed=seed,predictor=bool(seed&2))
            results.append(result)
        print(f"PASS fixed-seed random {seed}: cached/uncached",flush=True)
    # A, B and C map to the same set. Touch A => evict B, then B => evict A.
    elf=compile_asm("cache-lru","\n".join([
        "li x28,0x80040000","li x5,0x12345678",
        "sw x5,0(x28)","sw x5,512(x28)","lw x6,0(x28)",
        "sw x5,1024(x28)","lw x7,512(x28)","fence rw,rw","li a0,0"]))
    expected,end=oracle(elf)
    result=simulate(elf,"jitter",expected,end,latency=3,jitter=4)
    assert [result[k] for k in ("cache_hits","cache_misses","cache_writebacks")]==[1,4,3],result
    assert (result["backend_reads"],result["backend_writes"])==(32,24),result
    results.append(result)
    traps=[
        # name, prefix, faulting instruction, cause, tval, extra simulator flags, memory check
        ("ecall","","ecall",8,0,[],True),
        ("ebreak","","ebreak",3,0,[],True),
        ("illegal",""," .word 0xffffffff",2,0xffffffff,[],True),
        ("bad-shift",""," .word 0x02009093",2,0x02009093,[],True),
        ("bad-simd",""," .word 0x0000300b",2,0x0000300b,[],True),
        ("fence-i",""," .word 0x0000100f",2,0x0000100f,[],True),
        ("csr",""," .word 0xc0002573",2,0xc0002573,[],True),
        ("misaligned-lw","","lw x5,2(x28)",4,0x80040002,[],True),
        ("misaligned-lh","","lh x5,1(x28)",4,0x80040001,[],True),
        ("misaligned-sw","","sw x5,2(x28)",6,0x80040002,[],True),
        ("misaligned-sh","","sh x5,1(x28)",6,0x80040001,[],True),
        ("misaligned-jal","","jal x0,test_end+2",0,"pc+2",[],True),
        ("misaligned-jalr","li x5,0x80040003","jalr x0,0(x5)",0,0x80040002,[],True),
        ("load-fault","li x28,0x90000000","lw x0,0(x28)",5,0x90000000,[],True),
        ("store-fault","li x28,0x90000000","sw x5,0(x28)",7,0x90000000,[],True),
        ("refill-fault","","lw x5,0(x28)",5,0x80040000,["--fault-read","0x8004000c"],True),
        ("writeback-fault","sw x5,0(x28)\nsw x5,512(x28)",
         "lw x6,1024(x28)",5,0x80040400,["--fault-write","0x80040000"],False),
        ("flush-fault","sw x5,0(x28)","fence rw,rw",7,0x80040000,
         ["--fault-write","0x80040000"],False),
    ]
    for name,prefix,insn,cause,tval,options,memory in traps:
        elf=compile_asm(name,"li x28,0x80040000\nli x30,0x10000004\nli x5,77\n"+prefix,
                        insn,"sw x5,0(x30)\nsw x5,64(x28)\nj .")
        expected,end=oracle(elf)
        if tval=="pc+2": tval=end+2
        result=simulate(elf,"jitter",expected,end,cause=cause,tval=tval,
                        latency=3,jitter=4,options=options,memory=memory)
        assert result["mmio_writes"]==0,result
        results.append(result)
        print(f"PASS terminal trap {name}: cause={cause}, tval={tval:08x}",flush=True)
    # A missing instruction fetch is not a decoded illegal instruction.
    elf=compile_asm("fetch-fault","li x5,0x80100000\njalr x0,0(x5)",
                    "",absolute_end=0x80100000)
    expected,end=oracle(elf)
    result=simulate(elf,"jitter",expected,end,cause=1,tval=0x80100000,latency=2,jitter=3)
    results.append(result)
    elf=compile_asm("simd-disabled","li x5,1\nli x6,2",".insn r 0x0b,2,0,x7,x5,x6",
                    "sw x5,0(x0)")
    expected,end=oracle(elf)
    insn=0x0062a38b
    result=simulate(elf,"off",expected,end,simd=False,cause=2,tval=insn,jitter=2)
    results.append(result)
    missing=REQUIRED-set(coverage)
    assert not missing,sorted(missing)
    report=dict(configurations=len(results),commits=sum(x["retired"] for x in results),
                seeds=[1,7,42,73,101,257,65537,20261015],
                coverage=dict(sorted(coverage.items())),results=results)
    (BUILD/"regression-summary.json").write_text(json.dumps(report,indent=2)+"\n")
    print(f"PASS regression: {len(results)} configurations, {report['commits']} checked retirements, "
          f"{len(REQUIRED)} required instruction types")


if __name__=="__main__":
    main()
