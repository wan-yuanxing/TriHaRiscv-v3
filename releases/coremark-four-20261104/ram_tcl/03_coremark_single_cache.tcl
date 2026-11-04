# HARDWARE ACTION: run only after board connection; volatile FPGA Program + Verify.
# Requires a running local PDS JTAG server. Does not program Flash.
set root [file normalize [file join [file dirname [info script]] ..]]
set python python
if {[info exists ::env(TRIHA_PYTHON)]} {set python $::env(TRIHA_PYTHON)}
puts [exec $python [file join $root demo.py] verify]
cfg_connect -ip 127.0.0.1 -port 65420
cfg_scan_chain
set actual_id [cfg_read_device_property -mode 0]
if {![string equal -nocase $actual_id {00602899}]} {
    cfg_disconnect
    error "Target ID mismatch; nothing programmed"
}
cfg_assign_file -file [file join $root {images/03_coremark_single_cache/triha_cpu_ddr_board_top.sbit}] -device_index 0
cfg_program -device_index 0
cfg_verify -device_index 0
cfg_disconnect
puts "Read the native log: both cfg_program and cfg_verify must report success."
