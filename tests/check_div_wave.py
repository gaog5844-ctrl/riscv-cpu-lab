"""Check that the long-latency test actually exercised divider wait/hold paths.

Samples settled low-clock snapshots, not wall-clock ns. This is trace coverage,
not formal proof. Architectural correctness is checked separately with Spike.
"""
from collections import Counter
import json
from pathlib import Path
import subprocess

BUILD=Path(__file__).resolve().parents[1]/'build'
core='TOP.rv32_system.core.'
wanted={core+name:name for name in ('div_start','div_done','div_saved',
        'div_operands_ready','ex_fire','e_valid','ex_is_div')}
wanted.update({'TOP.clk':'clk','TOP.reset':'reset'})


def main():
    converted=subprocess.run(['fst2vcd',str(BUILD/'review-division-waits.fst')],
                             check=True,capture_output=True,text=True,timeout=30)
    scope=[]
    codes={}
    values={}
    counts=Counter()
    timestamp=None
    def sample():
        if values.get('clk')!=0 or values.get('reset')!=0: return
        if values.get('ex_is_div') and not values['div_operands_ready']:
            counts['load_operand_wait_cycles']+=1
        if values['e_valid'] and values['div_done'] and not values['ex_fire']:
            counts['completion_blocked_cycles']+=1
        if values['e_valid'] and values['div_saved'] and not values['ex_fire']:
            counts['saved_result_wait_cycles']+=1
        if values['div_saved'] and values['ex_fire']:
            counts['saved_result_release_cycles']+=1
        if values['div_start']:
            counts['start_cycles']+=1
            assert values['div_operands_ready'],('started without ready operands',timestamp)
    for raw in converted.stdout.splitlines():
        line=raw.strip()
        if line.startswith('$scope'): scope.append(line.split()[2])
        elif line.startswith('$upscope'): scope.pop()
        elif line.startswith('$var'):
            parts=line.split()
            full='.'.join(scope+[parts[4]])
            if full in wanted: codes[parts[3]]=wanted[full]
        elif line.startswith('$enddefinitions'):
            assert set(codes.values())==set(wanted.values()),codes
        elif line.startswith('#'):
            if timestamp is not None: sample()
            timestamp=int(line[1:])
        elif line and line[0] in '01xz':
            code=line[1:]
            if code in codes: values[codes[code]]=int(line[0]) if line[0] in '01' else None
    sample()
    for name in ('load_operand_wait_cycles','completion_blocked_cycles',
                 'saved_result_wait_cycles','saved_result_release_cycles','start_cycles'):
        assert counts[name]>0,('unexercised divider scenario',name,dict(counts))
    report=dict(kind='settled low-clock trace coverage, not formal verification',counts=dict(counts))
    (BUILD/'review-wave-summary.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS divider waveform coverage: '+json.dumps(dict(counts),sort_keys=True))


if __name__=='__main__': main()
