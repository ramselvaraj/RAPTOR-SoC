# Exploratory pre-layout constraints, not proven operating frequencies.
# No blanket asynchronous clock group: it would override Gray-pointer bounds.
set cpu_period [constraint_value DC_CPU_CLOCK_PERIOD 20.0]
set gpu_period [constraint_value DC_GPU_CLOCK_PERIOD 20.0]
if {$cpu_period <= 0 || $gpu_period <= 0} {error "Clock periods must be positive."}
create_clock -name cpu_clock -period $cpu_period [get_ports cpu_clk]
create_clock -name gpu_clock -period $gpu_period [get_ports gpu_clk]
set_clock_uncertainty -setup [constraint_value DC_SETUP_UNCERTAINTY 0.2] [all_clocks]
set_clock_uncertainty -hold [constraint_value DC_HOLD_UNCERTAINTY 0.05] [all_clocks]
set_clock_transition [constraint_value DC_CLOCK_TRANSITION 0.1] [all_clocks]

set gpu_inputs [get_ports gpu_program_rdata*]
set cpu_inputs [remove_from_collection [all_inputs] [add_to_collection $gpu_inputs [get_ports {cpu_clk gpu_clk}]]]
set gpu_outputs [filter_collection [all_outputs] {full_name =~ gpu_program_* || full_name =~ gpu_cycles*}]
set cpu_outputs [remove_from_collection [all_outputs] $gpu_outputs]
foreach domain {cpu gpu} {
    set inputs [set ${domain}_inputs]
    set outputs [set ${domain}_outputs]
    set_input_delay -max [constraint_value DC_INPUT_DELAY_MAX 4.0] -clock ${domain}_clock $inputs
    set_input_delay -min [constraint_value DC_INPUT_DELAY_MIN 0.0] -clock ${domain}_clock $inputs
    set_input_transition [constraint_value DC_INPUT_TRANSITION 0.1] $inputs
    set_output_delay -max [constraint_value DC_OUTPUT_DELAY_MAX 4.0] -clock ${domain}_clock $outputs
    set_output_delay -min [constraint_value DC_OUTPUT_DELAY_MIN 0.0] -clock ${domain}_clock $outputs
    set_load [constraint_value DC_OUTPUT_LOAD 0.01] $outputs
}

# Bound Gray-register -> first synchronizer data paths by the faster period.
# This is conservative for either source domain. Hold has no fixed phase.
set gray_first [get_cells -hierarchical -filter {full_name =~ *wg1_reg* || full_name =~ *rg1_reg*}]
if {[sizeof_collection $gray_first] == 0} {
    error "Cannot locate Gray synchronizers. Review naming before applying CDC exceptions."
}
set gray_d [get_pins -of_objects $gray_first -filter {full_name =~ */D}]
if {[sizeof_collection $gray_d] == 0} {error "Cannot locate Gray synchronizer D pins."}
set_max_delay [expr {min($cpu_period,$gpu_period)}] -datapath_only -to $gray_d
set_false_path -hold -to $gray_d

# Single-bit link-ready flags. Only the first stage is asynchronous.
set flag_first [get_cells -hierarchical -filter {full_name =~ *gpu_up_cpu_reg*0* || full_name =~ *cpu_up_gpu_reg*0*}]
if {[sizeof_collection $flag_first] == 0} {error "Cannot locate link-ready synchronizers."}
set flag_d [get_pins -of_objects $flag_first -filter {full_name =~ */D}]
set_false_path -to $flag_d

# Reset release uses local two-stage synchronizers. Keep recovery/removal checks
# visible for review rather than masking every asynchronous reset pin globally.
# The async FIFO payload is a stable bundled-data memory path: review its actual
# implementation and remaining cross-domain timing with structural CDC checks.
