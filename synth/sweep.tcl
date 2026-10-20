# Called by dc.tcl after configuring libraries and selecting the output directory.
# Re-analyze one saved implementation. Never compile or overwrite the baseline.
proc worst_slack {delay_type} {
    set paths [get_timing_paths -delay_type $delay_type -max_paths 1]
    if {[sizeof_collection $paths] == 0} {
        return NA
    }
    return [format %.6f [get_attribute $paths slack]]
}

proc run_constraint_sweep {top script_dir} {
    set mapped [file normalize results/soc_top.ddc]
    if {![file isfile $mapped]} {
        error "Missing $mapped. Run synthesis first or set DC_OUT_DIR."
    }
    file mkdir reports/sweep
    set summary [open reports/sweep/summary.csv w]
    puts $summary "case,period_ns,clock_slew_ns,setup_uncertainty_ns,hold_uncertainty_ns,setup_slack_ns,hold_slack_ns"
    # First four cases change one assumption at a time from the original run.
    # Input slew stays 1 ns, I/O delays stay 4 ns, load stays 0.01 pF.
    # These are sensitivity experiments, not measured clock/interface specs.
    set cases {
        {baseline_saved 20.0 1.0 1.0 1.0}
        {hold_only      20.0 1.0 1.0 0.05}
        {slew_only      20.0 0.1 1.0 1.0}
        {combined       20.0 0.1 1.0 0.05}
        {setup_margin   20.0 0.1 0.2 0.05}
        {period_15ns    15.0 0.1 0.2 0.05}
        {period_10ns    10.0 0.1 0.2 0.05}
    }
    foreach scenario $cases {
        lassign $scenario name period slew setup hold
        # Each case starts from the original mapped DDC, not the previous case.
        if {$name ne "baseline_saved"} {
            remove_design -all
        }
        read_ddc $mapped
        current_design $top
        if {![link]} {
            error "Cannot link mapped design for scenario $name."
        }
        if {$name ne "baseline_saved"} {
            reset_design
            set ::env(DC_CLOCK_PERIOD) $period
            set ::env(DC_CLOCK_TRANSITION) $slew
            set ::env(DC_SETUP_UNCERTAINTY) $setup
            set ::env(DC_HOLD_UNCERTAINTY) $hold
            set ::env(DC_INPUT_TRANSITION) 1.0
            set ::env(DC_INPUT_DELAY_MAX) 4.0
            set ::env(DC_INPUT_DELAY_MIN) 4.0
            set ::env(DC_OUTPUT_DELAY_MAX) 4.0
            set ::env(DC_OUTPUT_DELAY_MIN) 4.0
            set ::env(DC_OUTPUT_LOAD) 0.01
            source [file join $script_dir constraints.tcl]
        }
        set prefix reports/sweep/$name
        redirect -file ${prefix}_setup.rpt {
            report_timing -delay_type max -max_paths 3 -significant_digits 6
        }
        redirect -file ${prefix}_hold.rpt {
            report_timing -delay_type min -max_paths 3 -significant_digits 6
        }
        redirect -file ${prefix}_qor.rpt {report_qor}
        redirect -file ${prefix}_check_timing.rpt {check_timing}
        write_sdc ${prefix}.sdc
        set setup_slack [worst_slack max]
        set hold_slack [worst_slack min]
        # NA for saved settings: DDC constraints, not the labels above, govern it.
        if {$name eq "baseline_saved"} {
            puts $summary "$name,NA,NA,NA,NA,$setup_slack,$hold_slack"
        } else {
            puts $summary "$name,$period,$slew,$setup,$hold,$setup_slack,$hold_slack"
        }
        flush $summary
    }
    close $summary
    puts "Sweep complete: reports/sweep/summary.csv"
    puts "Same netlist, no recompilation. These experiments do not establish a signoff frequency."
}
