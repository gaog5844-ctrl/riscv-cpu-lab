#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
lab_root="$PWD"
lab_tools="$HOME/.local/opt/riscv-cpu-lab"
lab_cache="$HOME/.cache/riscv-cpu-lab"
spike_revision=f8a060b7bea8da6f738f193ed1b66b665978d092
mkdir -p "$lab_tools" "$lab_cache" build
if [ ! -d "$lab_cache/spike-src/.git" ]; then
  git clone https://github.com/riscv-software-src/riscv-isa-sim.git "$lab_cache/spike-src"
fi
git -C "$lab_cache/spike-src" checkout --detach "$spike_revision"
mkdir -p "$lab_cache/spike-build"
cd "$lab_cache/spike-build"
"$lab_cache/spike-src/configure" --prefix="$lab_tools/spike" --enable-commitlog
make -j2
make install
cd "$lab_root"
python3 -m venv "$lab_tools/venv"
"$lab_tools/venv/bin/python" -m pip install -r tools/requirements.txt
{
  date -u +%FT%TZ
  verilator --version
  iverilog -V 2>/dev/null | head -n 1 || true
  riscv64-unknown-elf-gcc --version | head -n 1
  printf 'spike_commit=%s\n' "$spike_revision"
  dpkg-query -W verilator iverilog gtkwave gcc g++ make gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
  "$lab_tools/venv/bin/python" -m pip freeze
} > build/toolchain-versions.txt
printf 'BOOTSTRAP_PASS\n'
