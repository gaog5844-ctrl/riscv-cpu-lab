SHELL := /bin/bash
LAB_TOOLS := $(HOME)/.local/opt/riscv-cpu-lab
PYTHON := $(if $(wildcard $(LAB_TOOLS)/venv/bin/python),$(LAB_TOOLS)/venv/bin/python,python3)
BUILD := build
RTL_UNITS := rtl/rv32_alu.sv rtl/rv32_simd.sv rtl/rv32_div.sv
RTL_CORE := $(RTL_UNITS) rtl/rv32_decode.sv rtl/rv32_bpu.sv rtl/rv32_core.sv
RTL_SYSTEM := $(RTL_CORE) rtl/rv32_dcache.sv rtl/rv32_system.sv
.PHONY: doctor unit test lint bench wave synth review oracle-test
doctor:
	@$(PYTHON) tools/doctor.py
unit: $(BUILD)/tb_units $(BUILD)/tb_cache $(BUILD)/tb_bpu $(BUILD)/tb_simd_math $(BUILD)/simd-vectors.txt
	vvp $(BUILD)/tb_units
	vvp $(BUILD)/tb_cache
	vvp $(BUILD)/tb_bpu
	vvp $(BUILD)/tb_simd_math
$(BUILD)/simd-vectors.txt: tests/simd_vectors.py
	$(PYTHON) tests/simd_vectors.py
$(BUILD)/tb_simd_math: rtl/rv32_simd.sv tests/unit/tb_simd_math.sv
	mkdir -p $(BUILD)
	iverilog -g2012 -s tb_simd_math -o $@ $^
$(BUILD)/tb_cache: rtl/rv32_dcache.sv tests/unit/tb_cache.sv
	mkdir -p $(BUILD)
	iverilog -g2012 -s tb_cache -o $@ $^
$(BUILD)/tb_bpu: rtl/rv32_bpu.sv tests/unit/tb_bpu.sv
	mkdir -p $(BUILD)
	iverilog -g2012 -s tb_bpu -o $@ $^
$(BUILD)/tb_units: $(RTL_UNITS) tests/unit/tb_units.sv
	mkdir -p $(BUILD)
	iverilog -g2012 -s tb_units -o $@ $^
lint:
	verilator --lint-only -Wall --top-module rv32_alu rtl/rv32_alu.sv
	verilator --lint-only -Wall --top-module rv32_div rtl/rv32_div.sv
	verilator --lint-only -Wall --top-module rv32_simd rtl/rv32_simd.sv
	verilator --lint-only -Wall --top-module rv32_decode rtl/rv32_decode.sv
	verilator --lint-only -Wall --top-module rv32_core $(RTL_CORE)
	verilator --lint-only -Wall --top-module rv32_system $(RTL_SYSTEM)
$(BUILD)/obj/Vrv32_system: $(RTL_SYSTEM) sim/main.cpp
	mkdir -p $(BUILD)
	verilator -Wall --cc --exe --build -j 2 --trace-fst --assert --top-module rv32_system --Mdir $(BUILD)/obj $(RTL_SYSTEM) $(abspath sim/main.cpp) -CFLAGS "-std=c++17 -O2"
$(BUILD)/obj-nosimd/Vrv32_system: $(RTL_SYSTEM) sim/main.cpp
	mkdir -p $(BUILD)
	verilator -Wall --cc --exe --build -j 2 --trace-fst --assert -GENABLE_SIMD=0 --top-module rv32_system --Mdir $(BUILD)/obj-nosimd $(RTL_SYSTEM) $(abspath sim/main.cpp) -CFLAGS "-std=c++17 -O2"
$(BUILD)/smoke.bin: tests/programs/smoke.S tests/programs/link.ld
	mkdir -p $(BUILD)
	riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -Wl,--no-relax -T tests/programs/link.ld $< -o $(BUILD)/smoke.elf
	riscv64-unknown-elf-objcopy -O binary $(BUILD)/smoke.elf $@
smoke: $(BUILD)/obj/Vrv32_system $(BUILD)/smoke.bin
	$(PYTHON) tests/run_smoke.py
$(BUILD)/xsimd.so: sim/spike_xsimd.cpp
	mkdir -p $(BUILD)
	g++ -std=c++20 -O2 -fPIC -shared -I$(LAB_TOOLS)/spike/include -I$(LAB_TOOLS)/spike/include/riscv $< -o $@
diff: smoke $(BUILD)/xsimd.so
	$(PYTHON) tests/spike_reference.py
regression: $(BUILD)/obj/Vrv32_system $(BUILD)/obj-nosimd/Vrv32_system $(BUILD)/xsimd.so
	$(PYTHON) tests/regression.py
oracle-test:
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py' -v
review: $(BUILD)/obj/Vrv32_system $(BUILD)/xsimd.so
	$(PYTHON) tests/review_regression.py
	$(PYTHON) tests/check_div_wave.py
test: lint unit oracle-test diff regression review
bench: $(BUILD)/obj/Vrv32_system $(BUILD)/xsimd.so
	$(PYTHON) benchmarks/run.py
wave: smoke
	@echo 'Generated build/smoke.fst. View with: gtkwave build/smoke.fst'
synth:
	@if command -v vivado >/dev/null; then vivado -mode batch -source tools/synth.tcl -notrace; \
	elif command -v powershell.exe >/dev/null; then powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w tools/synth.ps1)"; \
	else echo 'Vivado is optional and is not installed. RTL simulation does not require it.'; exit 2; fi
