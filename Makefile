SHELL := /bin/bash
LAB_TOOLS := $(HOME)/.local/opt/riscv-cpu-lab
PYTHON := $(if $(wildcard $(LAB_TOOLS)/venv/bin/python),$(LAB_TOOLS)/venv/bin/python,python3)
BUILD := build
RTL_UNITS := rtl/rv32_alu.sv rtl/rv32_simd.sv rtl/rv32_div.sv
RTL_CORE := $(RTL_UNITS) rtl/rv32_decode.sv rtl/rv32_bpu.sv rtl/rv32_core.sv
.PHONY: doctor unit test lint bench wave synth
doctor:
	@$(PYTHON) tools/doctor.py
unit: $(BUILD)/tb_units
	vvp $(BUILD)/tb_units
$(BUILD)/tb_units: $(RTL_UNITS) tests/unit/tb_units.sv
	mkdir -p $(BUILD)
	iverilog -g2012 -s tb_units -o $@ $^
lint:
	verilator --lint-only -Wall --top-module rv32_alu rtl/rv32_alu.sv
	verilator --lint-only -Wall --top-module rv32_div rtl/rv32_div.sv
	verilator --lint-only -Wall --top-module rv32_simd rtl/rv32_simd.sv
	verilator --lint-only -Wall --top-module rv32_decode rtl/rv32_decode.sv
	verilator --lint-only -Wall --top-module rv32_core $(RTL_CORE)
$(BUILD)/obj/Vrv32_core: $(RTL_CORE) sim/main.cpp
	mkdir -p $(BUILD)
	verilator -Wall --cc --exe --build -j 2 --trace-fst --assert --top-module rv32_core --Mdir $(BUILD)/obj $(RTL_CORE) $(abspath sim/main.cpp) -CFLAGS "-std=c++17 -O2"
$(BUILD)/smoke.bin: tests/programs/smoke.S tests/programs/link.ld
	mkdir -p $(BUILD)
	riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -Wl,--no-relax -T tests/programs/link.ld $< -o $(BUILD)/smoke.elf
	riscv64-unknown-elf-objcopy -O binary $(BUILD)/smoke.elf $@
smoke: $(BUILD)/obj/Vrv32_core $(BUILD)/smoke.bin
	$(PYTHON) tests/run_smoke.py
test: lint unit smoke
bench:
	@echo 'CPU benchmarks are not implemented yet'; exit 1
wave:
	@echo 'Run a CPU simulation with tracing first'; exit 1
synth:
	@echo 'Vivado synthesis is not yet validated; see docs/implementation.md'; exit 1
