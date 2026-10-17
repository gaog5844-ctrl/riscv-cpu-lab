"""Second-review counterexamples and targeted integration tests.

Separate from the original regression summary so historical counts stay comparable.
Every normal prefix is still checked with Spike, including before terminal faults.
"""
import csv
import json
from common import BUILD, compile_asm, records, reference, simulate, symbol


def nested_calls():
    body = "li sp,0x800ff000\nli a0,12\njal ra,sum_down\nfence rw,rw"
    tail = """
sum_down:
    addi sp,sp,-16
    sw ra,12(sp)
    sw a0,8(sp)
    beq a0,zero,base_case
    addi a0,a0,-1
    jal ra,sum_down
    lw t0,8(sp)
    add a0,a0,t0
    j return_sum
base_case:
    li a0,0
return_sum:
    lw ra,12(sp)
    addi sp,sp,16
    jalr zero,0(ra)
"""
    return compile_asm('review-nested-calls', body, tail=tail)


def indirect_alias():
    body = """
    li s0,20
    li s1,0
    li a0,0
    li t3,0x10000004
dispatch:
    xori s1,s1,1
    la t0,leaf_a
    bnez s1,chosen
    la t0,leaf_b
chosen:
    ori t0,t0,1
    jalr ra,0(t0)
    addi s0,s0,-1
    bnez s0,dispatch
    fence rw,rw
"""
    tail = """
    .balign 256
leaf_a:
    addi a0,a0,1
ret_a:
    jalr zero,0(ra)
    sw s0,0(t3)
    .balign 256
leaf_b:
    addi a0,a0,2
ret_b:
    jalr zero,0(ra)
    sw s0,0(t3)
"""
    elf = compile_asm('review-indirect-alias', body, tail=tail)
    assert (symbol(elf,'ret_a') & 255) == (symbol(elf,'ret_b') & 255)
    return elf


def division_waits():
    lines = ['li x28,0x80040000', 'li x30,0x10000004']
    for index, op in enumerate(('div','divu','rem','remu')):
        # Different lines force misses. Both operand dependencies, and rd=rs1.
        lines += ['li x5,1184','li x6,1', f'lw x6,{index*64}(x28)',
                  f'{op} x7,x5,x6', f'sw x7,{512+index*32}(x28)',
                  'li x5,123', f'lw x5,{index*64+32}(x28)',
                  f'{op} x5,x5,x6', f'sw x5,{640+index*32}(x28)']
    # Independent load stays in MEM long enough for a normal 32-step divide to finish.
    lines += ['li x5,100','li x6,3','lw x9,1024(x28)',
              'div a0,x5,x6','add a0,a0,x9','fence rw,rw']
    return compile_asm('review-division-waits','\n'.join(lines))


def main():
    BUILD.mkdir(exist_ok=True)
    results=[]
    def execute(elf, suffix, *, expected_a0=None, **options):
        expected, terminal = reference(elf, BUILD/(elf.stem+'-spike.log'))
        bus=BUILD/(elf.stem+'-'+suffix+'-bus.csv')
        extra=list(options.pop('options',())) + ['--bus-trace',str(bus)]
        result=simulate(elf,suffix,expected,terminal,options=extra,**options)
        assert result['mmio_writes']==0,result
        if expected_a0 is not None: assert result['a0']==expected_a0,result
        with bus.open() as stream:
            requests=list(csv.DictReader(stream))
        fetches=[int(row['address'],16) for row in requests if row['port']=='I']
        assert fetches and all(address%4==0 for address in fetches),(elf.name,fetches)
        result['aligned_fetch_requests']=len(fetches)
        results.append(result)
        print(f"PASS review {result['name']}: {result['retired']} commits; {len(fetches)} aligned fetches",flush=True)
        return fetches

    for factory, answer in ((nested_calls,78),(indirect_alias,30)):
        elf=factory()
        for cache in (False,True):
            for predict in (False,True):
                for latency,jitter in ((1,0),(3,7)):
                    suffix=f'c{int(cache)}p{int(predict)}l{latency}j{jitter}'
                    execute(elf,suffix,cache=cache,predictor=predict,latency=latency,
                            jitter=jitter,seed=73,expected_a0=answer)

    # bit 0 is cleared; bit 1 is not. The exception belongs to JALR, not its target.
    for low in (2,3):
        elf=compile_asm(f'review-jalr-low{low}',f'li x5,0x8004000{low}\nli ra,85',
                        'jalr ra,0(x5)','sw ra,0(x0)\nj .')
        for predict in (False,True):
            fetches=execute(elf,f'p{int(predict)}',predictor=predict,latency=3,jitter=7,
                            cause=0,tval=0x80040002)
            assert 0x80040002 not in fetches and 0x80040003 not in fetches

    elf=division_waits()
    for cache in (False,True):
        for latency,jitter in ((1,0),(40,7)):
            suffix=f'c{int(cache)}l{latency}'
            options=['--wave',str(BUILD/'review-division-waits.fst')] if cache and latency==40 else []
            execute(elf,suffix,cache=cache,latency=latency,jitter=jitter,expected_a0=33,options=options)

    # The older load fault must squash a waiting divide and both younger stores.
    elf=compile_asm('review-load-fault-div','li x28,0x90000000\nli x30,0x10000004\nli x6,3',
                    'lw x5,0(x28)','div x7,x5,x6\nsw x7,0(x30)\nsw x7,0(x0)\nj .')
    execute(elf,'delayed',latency=40,jitter=7,cause=5,tval=0x90000000)

    summary=dict(configurations=len(results),commits=sum(row['retired'] for row in results),results=results)
    (BUILD/'review-regression-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f"PASS review regression: {summary['configurations']} configurations, {summary['commits']} checked retirements")


if __name__=='__main__':
    main()
