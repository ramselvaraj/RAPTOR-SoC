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
    set directory reports/cpu_100mhz
    set boot_contract [expr {[env_or DC_BOOT_CONTRACT 0] eq "1"}]
    set memory_contract [expr {[env_or DC_MEMORY_CONTRACT 0] eq "1"}]
    if {$boot_contract} {
        # Interface requirement, not inserted delay or a hold-path exception.
        # A real boot source must guarantee this minimum arrival/hold budget.
        set boot_inputs [get_ports {boot_addr* boot_wdata* boot_sel* boot_valid}]
        if {[sizeof_collection $boot_inputs] == 0} {error "Boot input collection is empty."}
        set_input_delay -min 0.1 -clock cpu_clock $boot_inputs
        set directory reports/cpu_100mhz_boot_contract
    }
    if {$memory_contract} {
        if {!$boot_contract} {error "Memory-interface check requires the explicit boot contract too."}
        set memory_inputs [get_ports {cpu_imem_rdata* ram_host_rdata* ram_px_rdata*}]
        if {[sizeof_collection $memory_inputs] == 0} {error "CPU memory read-data input collection is empty."}
        set_input_delay -min 0.1 -clock cpu_clock $memory_inputs
        set directory reports/cpu_100mhz_interfaces
    }
    file mkdir $directory
    set fd [open $directory/summary.txt w]
    puts $fd "Saved netlist re-analysis; no resynthesis."
    puts $fd "CPU: 10 ns / 100 MHz. GPU target retained: 20 ns / 50 MHz."
    puts $fd "CPU reports include internal, interface, and non-excepted cross-domain paths ending in cpu_clock."
    puts $fd "GPU timing is not re-reported by this focused command."
    puts $fd "Gray-pointer maximum delay follows the faster clock period (10 ns)."
    puts $fd "Library capacitance limits remain unchanged."
    if {$boot_contract} {
        puts $fd "Conditional boot contract: minimum input delay 0.1 ns on boot_addr, boot_wdata, boot_sel, boot_valid."
        puts $fd "Existing maximum delays and all hold checks remain unchanged."
        puts $fd "This does not implement a boot driver or prove that a physical source meets the contract."
    }
    if {$memory_contract} {
        puts $fd "Conditional memory contract: CPU instruction, RAM host, and RAM pixel read-data arrival window is 0.1..4.0 ns."
        puts $fd "This is a requirement for external memory timing, not characterized memory behavior."
        puts $fd "GPU program-data timing is unchanged; this check does not establish GPU setup/hold closure."
    }
    puts $fd "Input minimum delays outside the stated contracts remain zero."
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
