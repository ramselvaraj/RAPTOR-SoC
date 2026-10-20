# Focused whole-CPU-domain re-analysis. No exhaustive from/to collections.
proc run_phase5_cpu_check {} {
    set mapped [file normalize results/soc_phase5_top.ddc]
    if {![file isfile $mapped]} {error "Missing $mapped. Run dc-phase5-core first."}
    read_ddc $mapped
    current_design soc_phase5_top
    if {![link]} {error "Cannot link saved Phase 5 design."}
    reset_design
    # Keep the Phase 5 baseline assumptions; change only CPU period to 10 ns.
    set ::env(DC_CPU_CLOCK_PERIOD) 10.0
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
    file mkdir reports/cpu_100mhz
    set directory reports/cpu_100mhz
    set fd [open $directory/summary.txt w]
    puts $fd "Saved netlist re-analysis; no resynthesis."
    puts $fd "CPU: 10 ns / 100 MHz. GPU target retained: 20 ns / 50 MHz."
    puts $fd "CPU reports include internal, interface, and non-excepted cross-domain paths ending in cpu_clock."
    puts $fd "GPU timing is not re-reported by this focused command."
    puts $fd "Gray-pointer maximum delay follows the faster clock period (10 ns)."
    puts $fd "Library capacitance limits remain unchanged."
    flush $fd
    foreach kind {max min} label {setup hold} {
        puts "Reporting CPU-domain $label timing..."
        redirect -variable text {
            report_timing -group cpu_clock -delay_type $kind -max_paths 1 -significant_digits 6
        }
        set report [open $directory/cpu_${label}.rpt w]
        puts $report $text
        close $report
        if {[regexp {slack[[:space:]]+\((MET|VIOLATED)\)[[:space:]]+([-+0-9.eE]+)} $text -> status slack]} {
            puts $fd "CPU $label slack: $slack ns ($status)"
        } else {
            puts $fd "CPU $label slack: NA (no parsed path; inspect report, do not treat as passing)"
        }
        flush $fd
    }
    close $fd
    redirect -file $directory/check_timing.rpt {check_timing}
    redirect -file $directory/clocks.rpt {report_clock -attributes}
    write_sdc $directory/constraints.sdc
    puts "Focused check complete: $directory/summary.txt"
}
