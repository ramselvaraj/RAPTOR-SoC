# Starting constraints only. Validate against the selected library and board.
# Time values use the technology library's time unit (normally ns).
set period [env_or DC_CLOCK_PERIOD 20.0]
if {![string is double -strict $period] || $period <= 0} {
    error "DC_CLOCK_PERIOD must be positive."
}
create_clock -name core_clk -period $period [get_ports clk]
set_clock_uncertainty [expr {$period * 0.05}] [get_clocks core_clk]
set_clock_transition [expr {$period * 0.05}] [get_clocks core_clk]

set data_inputs [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay [expr {$period * 0.20}] -clock core_clk $data_inputs
set_input_transition [expr {$period * 0.05}] $data_inputs
set_output_delay [expr {$period * 0.20}] -clock core_clk [all_outputs]
# Load uses the technology library's capacitance unit (normally pF).
set_load 0.01 [all_outputs]

# Do not tie reset or the boot port to constants. Both are functional inputs.
# The boot port writes memories while reset=1. A reset case analysis would
# remove the hardware initialization path and invalidate the resulting netlist.
