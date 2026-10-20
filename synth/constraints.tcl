# Starting constraints only. Validate against the selected library and board.
# Time values use the technology library's time unit (normally ns).
proc constraint_value {name fallback} {
    set value [env_or $name $fallback]
    if {![string is double -strict $value] || !($value >= 0 && $value < 1e9)} {
        error "$name must be a finite nonnegative number."
    }
    return $value
}
set period [constraint_value DC_CLOCK_PERIOD 20.0]
if {$period <= 0} {
    error "DC_CLOCK_PERIOD must be positive."
}
create_clock -name core_clk -period $period [get_ports clk]
set setup_margin [constraint_value DC_SETUP_UNCERTAINTY [expr {$period * 0.05}]]
set hold_margin [constraint_value DC_HOLD_UNCERTAINTY [expr {$period * 0.05}]]
set clock_slew [constraint_value DC_CLOCK_TRANSITION [expr {$period * 0.05}]]
set input_slew [constraint_value DC_INPUT_TRANSITION [expr {$period * 0.05}]]
set input_max [constraint_value DC_INPUT_DELAY_MAX [expr {$period * 0.20}]]
set input_min [constraint_value DC_INPUT_DELAY_MIN $input_max]
set output_max [constraint_value DC_OUTPUT_DELAY_MAX [expr {$period * 0.20}]]
set output_min [constraint_value DC_OUTPUT_DELAY_MIN $output_max]
set output_load [constraint_value DC_OUTPUT_LOAD 0.01]
if {$input_min > $input_max || $output_min > $output_max} {
    error "Minimum I/O delays must not exceed maximum I/O delays."
}
set_clock_uncertainty -setup $setup_margin [get_clocks core_clk]
set_clock_uncertainty -hold $hold_margin [get_clocks core_clk]
set_clock_transition $clock_slew [get_clocks core_clk]

set data_inputs [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay -max $input_max -clock core_clk $data_inputs
set_input_delay -min $input_min -clock core_clk $data_inputs
set_input_transition $input_slew $data_inputs
set_output_delay -max $output_max -clock core_clk [all_outputs]
set_output_delay -min $output_min -clock core_clk [all_outputs]
# Load uses the technology library's capacitance unit (normally pF).
set_load $output_load [all_outputs]

# Do not tie reset or the boot port to constants. Both are functional inputs.
# The boot port writes memories while reset=1. A reset case analysis would
# remove the hardware initialization path and invalidate the resulting netlist.
