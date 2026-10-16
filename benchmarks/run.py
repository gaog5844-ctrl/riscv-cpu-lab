"""Actual RTL cycles, identical data/flags, independent integer golden outputs."""
from pathlib import Path
import json
import random
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tests"))
from common import ROOT, BUILD, compile_sources, records, reference, simulate, symbol


def inputs():
    rng=random.Random(20261015)
    n,rows,cols,stride=259,12,67,68
    a=[rng.randrange(-128,128) for _ in range(n)]
    b=[rng.randrange(-128,128) for _ in range(n)]
    vector=[rng.randrange(-128,128) for _ in range(cols)]
    matrix=[[rng.randrange(-128,128) for _ in range(cols)] for _ in range(rows)]
    dot=sum(x*y for x,y in zip(a,b))
    add=[(x+y)&255 for x,y in zip(a,b)]
    gemv=[sum(x*y for x,y in zip(row,vector)) for row in matrix]
    def array(kind,name,values):
        return f"__attribute__((aligned(32),used)) const {kind} {name}[{len(values)}] = {{"+",".join(map(str,values))+"};\n"
    header=f"#define N {n}\n#define ROWS {rows}\n#define COLS {cols}\n#define STRIDE {stride}\n"
    header+=array("int8_t","input_a",a)+array("int8_t","input_b",b)
    header+=array("int8_t","vector",vector+[0])
    header+=f"__attribute__((aligned(32),used)) const int8_t matrix[ROWS][STRIDE]={{"
    header+=",".join("{"+",".join(map(str,row+[0]))+"}" for row in matrix)+"};\n"
    header+=f"__attribute__((used)) const int32_t expected_dot={dot};\n"
    header+=array("uint8_t","expected_add",add)+array("int32_t","expected_gemv",gemv)
    (BUILD/"bench_inputs.h").write_text(header)
    return dict(seed=20261015,n=n,rows=rows,cols=cols,stride=stride,dot=dot,gemv=gemv,
                add_checksum=sum(add))


def main():
    BUILD.mkdir(exist_ok=True)
    golden=inputs()
    results=[]
    for kind,name in enumerate(["dot8","add8","gemv8"]):
        addresses=None
        for simd in [0,1]:
            mode="simd" if simd else "scalar"
            elf=compile_sources(f"bench-{name}-{mode}",
                                [ROOT/"benchmarks/start.S",ROOT/"benchmarks/kernels.c"],
                                [f"-DKERNEL={kind}",f"-DSIMD={simd}","-I"+str(BUILD)],
                                ROOT/"benchmarks/link.ld")
            layout={key:symbol(elf,key) for key in ["input_a","input_b","vector","matrix",
                                                  "output_add","output_dot","output_gemv"]}
            if addresses is None: addresses=layout
            assert addresses==layout,(name,"data address mismatch",addresses,layout)
            expected,end=reference(elf,BUILD/(elf.stem+"-spike.log"))
            start,stop=symbol(elf,"kernel_start"),symbol(elf,"kernel_end")
            for cache in [False,True]:
                for latency in [1,5]:
                    suffix=f"c{int(cache)}l{latency}"
                    result=simulate(elf,suffix,expected,end,cache=cache,latency=latency)
                    assert result["a0"]==0,(name,mode,"Python golden output mismatch",result)
                    trace=records(BUILD/(elf.stem+"-"+suffix+".csv"))
                    first=next(i for i,r in enumerate(trace) if r["pc"]==start)
                    last=next(i for i,r in enumerate(trace) if r["pc"]==stop)
                    result.update(kernel=name,variant=mode,
                                  kernel_cycles=trace[last]["cycle"]-trace[first]["cycle"],
                                  kernel_instructions=last-first)
                    results.append(result)
                    print(f"PASS {name}/{mode}/{suffix}: {result['kernel_cycles']} kernel cycles; golden+Spike+RAM",flush=True)
    comparisons=[]
    for name in ["dot8","add8","gemv8"]:
        for cache in [False,True]:
            for latency in [1,5]:
                pair={r["variant"]:r for r in results if r["kernel"]==name and
                      r["cache_enabled"]==cache and r["memory_latency"]==latency}
                a,b=pair["scalar"],pair["simd"]
                comparisons.append(dict(kernel=name,cache=cache,latency=latency,
                    scalar_cycles=a["kernel_cycles"],simd_cycles=b["kernel_cycles"],
                    speedup=a["kernel_cycles"]/b["kernel_cycles"],
                    scalar_instructions=a["kernel_instructions"],simd_instructions=b["kernel_instructions"]))
    report=dict(golden=golden,compiler_flags="-O2 -march=rv32im -mabi=ilp32 -mno-relax",
                measurement="Retirement of kernel_start through before kernel_end; includes call/return and FENCE writeback",
                configurations=results,comparisons=comparisons)
    (BUILD/"benchmarks.json").write_text(json.dumps(report,indent=2)+"\n")
    lines=["# SIMD 性能测试结果","",
           "标量与 SIMD 版本使用相同的数据地址、GCC 参数和内存设置。表中统计仿真周期，未测板级频率和功耗。","",
           "|内核|缓存|后端延迟|标量周期|SIMD 周期|周期加速比|标量/SIMD 指令数|",
           "|---|---|---|---|---|---|---|"]
    for r in comparisons:
        lines.append(f"|{r['kernel']}|{'开' if r['cache'] else '关'}|{r['latency']}|{r['scalar_cycles']}|"
                     f"{r['simd_cycles']}|{r['speedup']:.2f}×|{r['scalar_instructions']}/{r['simd_instructions']}|")
    (BUILD/"benchmarks.md").write_text("\n".join(lines)+"\n")
    print(f"PASS benchmarks: {len(results)} configurations; see build/benchmarks.md")


if __name__=="__main__":
    main()
