#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential verilator iverilog gtkwave \
  python3-venv python3-pip git ca-certificates device-tree-compiler \
  libboost-regex-dev libboost-system-dev libboost-program-options-dev \
  libgmp-dev libmpfr-dev libmpc-dev zlib1g-dev \
  gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
