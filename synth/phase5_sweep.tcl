# Analyze the existing implementation, not a new mapping at each frequency.
proc phase5_path_slack {kind from to} {
    set paths [get_timing_paths -delay_type $kind -from $from -to $to -max_paths 1]
    if {[sizeof_collection $paths] == 0} {return NA}
    set worst ""
    foreach_in_collection path $paths {
        set slack [get_attribute $path slack]
        if {$worst eq "" || $slack < $worst} {set worst $slack}
    }
    return [format %.6f $worst]
}

proc run_phase5_sweep {script_dir} {
    set mapped [file normalize results/soc_phase5_top.ddc]
    if {![file isfile $mapped]} {error "Missing $mapped. Run dc-phase5-core first."}
    file mkdir reports/cpu_sweep
    set summary [open reports/cpu_sweep/summary.csv w]
    puts $summary "case,cpu_period_ns,gpu_period_ns,path_class,setup_slack_ns,hold_slack_ns"
    foreach scenario {baseline_saved cpu_20ns cpu_15ns cpu_10ns cpu_5ns} {
        if {$scenario ne "baseline_saved"} {remove_design -all}
        read_ddc $mapped
        current_design soc_phase5_top
        if {![link]} {error "Cannot link saved Phase 5 design."}
        if {$scenario ne "baseline_saved"} {
            regexp {cpu_([0-9]+)ns} $scenario -> period
            reset_design
            # Hold every other assumption fixed. These match the Phase 5
            # defaults, but the saved baseline may have user overrides.
            set ::env(DC_CPU_CLOCK_PERIOD) $period
            set ::env(DC_GPU_CLOCK_PERIOD) 20.0
            set ::env(DC_SETUP_UNCERTAINTY) 0.2
            set ::env(DC_HOLD_UNCERTAINTY) 0.05
            set ::env(DC_CLOCK_TRANSITION) 0.1
            set ::env(DC_INPUT_TRANSITION) 0.1
            set ::env(DC_INPUT_DELAY_MAX) 4.0
            set ::env(DC_INPUT_DELAY_MIN) 0.0
            set ::env(DC_OUTPUT_DELAY_MAX) 4.0
            set ::env(DC_OUTPUT_DELAY_MIN) 0.0
            set ::env(DC_OUTPUT_LOAD) 0.01
            apply_phase5_constraints
        }
        set cpu_period [get_attribute [get_clocks cpu_clock] period]
        set gpu_period [get_attribute [get_clocks gpu_clock] period]
        # Register-role queries work with mapped library cells without relying
        # on instance prefixes or hard-coded data-pin names.
        set cpu_q [all_registers -clock cpu_clock -output_pins]
        set cpu_d [all_registers -clock cpu_clock -data_pins]
        set gpu_q [all_registers -clock gpu_clock -output_pins]
        set gpu_d [all_registers -clock gpu_clock -data_pins]
        foreach collection [list $cpu_q $cpu_d $gpu_q $gpu_d] {
            if {[sizeof_collection $collection] == 0} {
                error "Missing clock-specific register pins; cannot produce trustworthy internal timing."
            }
        }
        set prefix reports/cpu_sweep/$scenario
        file mkdir $prefix
        write_sdc $prefix/constraints.sdc
        redirect -file $prefix/clocks.rpt {report_clock -attributes}
        redirect -file $prefix/check_timing.rpt {check_timing}
        redirect -file $prefix/qor.rpt {report_qor}
        set classes [list \
            [list cpu_internal $cpu_q $cpu_d] \
            [list gpu_internal $gpu_q $gpu_d] \
            [list inputs_to_cpu [all_inputs] $cpu_d] \
            [list inputs_to_gpu [all_inputs] $gpu_d] \
            [list cpu_to_outputs $cpu_q [all_outputs]] \
            [list gpu_to_outputs $gpu_q [all_outputs]] \
            [list port_feedthrough [all_inputs] [all_outputs]] \
            [list cdc_cpu_to_gpu $cpu_q $gpu_d] \
            [list cdc_gpu_to_cpu $gpu_q $cpu_d]]
        foreach category $classes {
            lassign $category name from to
            set setup [phase5_path_slack max $from $to]
            set hold [phase5_path_slack min $from $to]
            puts $summary "$scenario,$cpu_period,$gpu_period,$name,$setup,$hold"
            if {$setup ne "NA"} {
                redirect -file $prefix/${name}_setup.rpt {
                    report_timing -delay_type max -from $from -to $to -max_paths 5 -significant_digits 6
                }
            }
            if {$hold ne "NA"} {
                redirect -file $prefix/${name}_hold.rpt {
                    report_timing -delay_type min -from $from -to $to -max_paths 5 -significant_digits 6
                }
            }
        }
        flush $summary
    }
    close $summary
    puts "Phase 5 sweep complete: reports/cpu_sweep/summary.csv"
    puts "Internal rows exclude ports and cross-clock paths. Review interface and CDC rows separately."
    puts "NA means no analyzed path, not a passing path. No netlist was recompiled or overwritten."
}
