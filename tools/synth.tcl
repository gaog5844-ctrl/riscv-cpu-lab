# Core-only synthesis: no board pins, DDR, UART, or bitstream.
set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
if {[info exists ::env(LAB_SYNTH_OUTPUT)]} {
    set output $::env(LAB_SYNTH_OUTPUT)
} else {
    set run_id "[clock format [clock seconds] -format %Y%m%d-%H%M%S]-[pid]"
    set output [file join $root build synth runs $run_id]
}
if {$::tcl_platform(platform) eq "windows" && [regexp {[^\x00-\x7F]} $output]} {
    error "Use an ASCII-only output path for Windows Vivado synthesis."
}
file mkdir $output
set_param project.keepTmpDir true
# Installed diagnostic device, not the report's unavailable Kintex-7 platform.
set part xc7a35tcsg324-1
if {[info exists ::env(LAB_FPGA_PART)]} { set part $::env(LAB_FPGA_PART) }
set period 10.000
if {[info exists ::env(LAB_SYNTH_PERIOD_NS)]} { set period $::env(LAB_SYNTH_PERIOD_NS) }
if {![string is double -strict $period] || $period <= 0} { error "Invalid clock period" }
if {[llength [get_parts -quiet $part]] != 1} { error "FPGA part is not installed: $part" }
read_verilog -sv [glob rtl/*.sv]
# Workaround tested with Windows Vivado 2026.1 and a non-ASCII hostname.
# Both the RTL temp path and the post-elaboration cache need an ASCII path.
# These are internal synthesis options; recheck after upgrading Vivado.
if {$::tcl_platform(platform) eq "windows" && [regexp {[^\x00-\x7F]} [info hostname]]} {
    set alias [file normalize [file join $output rt-native]]
    file mkdir [file join $alias tmp]
    set previous_options [get_param synth.elaboration.rodinMoreOptions]
    set workaround [format {
        set original_rt [rt::get_parameter enableSplitFlowPath]
        if {[file exists [file join $original_rt elab.rtd]]} {
            file copy -force [file join $original_rt elab.rtd] {%s/elab.rtd}
            puts "SYNTH_ELAB_CACHE_COPIED"
        }
        set ::env(RT_TMP) {%s/tmp}
        rt::set_parameter enableSplitFlowPath {%s/}
    } $alias $alias $alias]
    set_param synth.elaboration.rodinMoreOptions "$previous_options\n$workaround"
}
set constraints [file join $output clock.xdc]
set xdc [open $constraints w]
puts $xdc [format {create_clock -name clk -period %s [get_ports clk]} $period]
close $xdc
read_xdc $constraints
if {[catch {synth_design -top rv32_system -part $part -mode out_of_context -flatten_hierarchy rebuilt} failure options]} {
    set trace [open [file join $output failure.txt] w]
    puts $trace [dict get $options -errorinfo]
    close $trace
    return -options $options $failure
}
report_utilization -file [file join $output utilization.txt]
report_timing_summary -file [file join $output timing.txt]
set checkpoint [file join $output rv32_system.dcp]
write_checkpoint -force $checkpoint
close_design
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne $part} { error "Checkpoint part mismatch" }
if {[llength [get_cells -hierarchical]] == 0} { error "Empty synthesis checkpoint" }
if {[llength [get_clocks clk]] != 1} { error "Clock missing from checkpoint" }
set result [open [file join $output SYNTH_PASS.txt] w]
puts $result "SYNTH_PASS: $part, ${period}ns constraint, checkpoint reopened; not routed or board-tested"
close $result
exit
