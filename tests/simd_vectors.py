"""Python-integer golden vectors, independent of RTL and the Spike extension."""
from pathlib import Path
import random

BUILD=Path(__file__).resolve().parents[1]/'build'


def golden(op,a,b):
    aa=a.to_bytes(4,'little')
    bb=b.to_bytes(4,'little')
    if op==2:
        x=[int.from_bytes(aa[i:i+1],'little',signed=True) for i in range(4)]
        y=[int.from_bytes(bb[i:i+1],'little',signed=True) for i in range(4)]
        return sum(p*q for p,q in zip(x,y)) & 0xffffffff
    width=1 if op==0 else 2
    result=bytearray()
    for i in range(0,4,width):
        value=int.from_bytes(aa[i:i+width],'little')+int.from_bytes(bb[i:i+width],'little')
        result.extend((value % (256**width)).to_bytes(width,'little'))
    return int.from_bytes(result,'little')


def main():
    BUILD.mkdir(exist_ok=True)
    count=0
    with (BUILD/'simd-vectors.txt').open('w') as stream:
        def emit(op,a,b):
            nonlocal count
            stream.write(f'{op:x} {a:08x} {b:08x} {golden(op,a,b):08x}\n')
            count+=1
        edges=[0,0xffffffff,0x80808080,0x7f7f7f7f,0x80007fff]
        for a in edges:
            for b in edges:
                for op in range(3): emit(op,a,b)
        rng=random.Random(20261016)
        for _ in range(1024):
            a,b=rng.getrandbits(32),rng.getrandbits(32)
            for op in range(3): emit(op,a,b)
        # Every signed INT8 product, repeated in four lanes, includes both sum extremes.
        for x in range(256):
            for y in range(256):
                emit(2,int.from_bytes(bytes([x])*4,'little'),int.from_bytes(bytes([y])*4,'little'))
    assert count==68683
    print(f'Generated {count} independent SIMD golden vectors')


if __name__=='__main__': main()
