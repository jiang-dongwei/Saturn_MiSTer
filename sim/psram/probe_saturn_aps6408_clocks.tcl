project_open Saturn_APS6408 -revision Saturn_APS6408
foreach command {create_timing_netlist create_generated_clock get_clock_info get_pin_info get_clocks set_case_analysis get_register_info get_edge_info get_nets get_fanins} {
    puts "=== QUARTUS 17 HELP: $command ==="
    if {[catch {$command -long_help} result]} { puts "HELP ERROR: $result" } else { puts $result }
}
create_timing_netlist -post_map
read_sdc
update_timing_netlist

puts "=== PSRAM PLL CLOCKS AND TARGETS ==="
foreach_in_collection clock [get_clocks {*psram_speed_pll* FPGA_CLK2_50}] {
    puts "CLOCK [get_clock_info -name $clock] PERIOD [get_clock_info -period $clock]"
    if {[catch {get_clock_info -targets $clock} targets]} {
        puts "TARGET QUERY ERROR: $targets"
    } else {
        puts "TARGETS $targets"
        foreach_in_collection target $targets {
            if {[catch {get_node_info -name $target} name]} { puts "NODE QUERY ERROR: $name" } else { puts "TARGET $name" }
        }
    }
}
puts "=== CLOCK CONTROL PINS ==="
set pins [get_pins -no_duplicates {*psram_clock_control*}]
puts "PIN COUNT [get_collection_size $pins]"
foreach_in_collection pin $pins { puts "PIN [get_pin_info -name $pin]" }
puts "=== CLOCK CONTROL NETS ==="
set nets [get_nets {*psram_clock_control* *psram_engine_clk*}]
puts "NET COUNT [get_collection_size $nets]"
foreach_in_collection net $nets { puts "NET [get_net_info -name $net]" }
puts "=== CLOCK CONTROL KEEPERS ==="
set keepers [get_keepers {*psram_clock_control* *psram_engine_clk*}]
puts "KEEPER COUNT [get_collection_size $keepers]"
foreach_in_collection keeper $keepers { puts "KEEPER [get_node_info -name $keeper]" }
if {[llength [info procs set_case_analysis]] != 0} { puts "CASE ANALYSIS BODY: [info body set_case_analysis]" }

puts "=== ENGINE CLOCK REGISTER PINS ==="
set pins [get_pins -no_duplicates {*|ramh_psram|engine|PSRAM_CLK|*}]
foreach_in_collection pin $pins { puts "PIN [get_pin_info -name $pin]" }
set registers [get_registers {*|ramh_psram|engine|edge_index*}]
foreach_in_collection reg $registers {
    puts "REG [get_register_info -name $reg]"
    if {[catch {get_register_info -clock $reg} clocks]} {
        puts "REGISTER CLOCK QUERY ERROR: $clocks"
    } else {
        puts "REGISTER CLOCK $clocks"
        if {[catch {get_edge_info -src $clocks} source]} { puts "CLOCK SOURCE QUERY ERROR: $source" } else { puts "CLOCK SOURCE [get_node_info -name $source]" }
    }
}
puts "APS6408 CLOCK PROBE COMPLETE: post-map inspection only; no fitted timing or hardware verdict"
delete_timing_netlist
project_close
