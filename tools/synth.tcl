# Out-of-context diagnostic only: no board pins, DDR, UART, or bitstream.
set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
file mkdir build/synth
# Installed diagnostic device, not the report's unavailable Kintex-7 platform.
set part xc7a35tcsg324-1
if {[info exists ::env(LAB_FPGA_PART)]} { set part $::env(LAB_FPGA_PART) }
read_verilog -sv [glob rtl/*.sv]
synth_design -top rv32_system -part $part -mode out_of_context -flatten_hierarchy rebuilt
create_clock -name clk -period 10.000 [get_ports clk]
report_utilization -file build/synth/utilization.txt
report_timing_summary -file build/synth/timing.txt
write_checkpoint -force build/synth/rv32_system.dcp
set result [open build/synth/SYNTH_PASS.txt w]
puts $result "SYNTH_PASS: out-of-context $part; not place-and-route, not board verification"
close $result
exit
