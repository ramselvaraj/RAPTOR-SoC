# Reuse the preserved CPU result's exact implementation and constraints.
# Do not silently reconstruct or relax interface budgets to get a passing GPU.
proc run_phase5_gpu_check {repo_dir} {
    set mapped [file normalize results/soc_phase5_top.ddc]
    set saved [file join $repo_dir synth results phase5 cpu_100mhz_interfaces]
    foreach required [list $mapped [file join $saved constraints.sdc] [file join $saved netlist.sha256]] {
        if {![file isfile $required]} {error "Missing required baseline file: $required"}
    }
    set fd [open [file join $saved netlist.sha256] r]
    set expected [lindex [split [string trim [read $fd]]] 0]
    close $fd
    set actual [lindex [split [exec sha256sum $mapped]] 0]
    if {$actual ne $expected} {
        error "Mapped DDC does not match the preserved CPU result. Do not mix results from different netlists."
    }
    read_ddc $mapped
    current_design soc_phase5_top
    if {![link]} {error "Cannot link the preserved implementation."}
    reset_design
    if {![read_sdc [file join $saved constraints.sdc]]} {error "Cannot read preserved CPU constraints."}
    set directory reports/gpu_50mhz
    file mkdir $directory
    set summary [open $directory/summary.txt w]
    puts $summary "Saved-netlist re-analysis using the preserved CPU result's exact SDC."
    puts $summary "DDC SHA256: $actual"
    puts $summary "CPU period: [get_attribute [get_clocks cpu_clock] period] ns"
    puts $summary "GPU period: [get_attribute [get_clocks gpu_clock] period] ns"
    puts $summary "No clock margins, interface budgets, exceptions, or library limits changed."
    puts $summary "CPU is re-reported as a control. GPU program-data minimum input delay remains at the saved value."
    flush $summary
    foreach domain {cpu gpu} {
        foreach kind {max min} label {setup hold} {
            puts "Reporting $domain $label timing..."
            redirect -variable text {
                report_timing -group ${domain}_clock -delay_type $kind -max_paths 1 -significant_digits 6
            }
            set fd [open $directory/${domain}_${label}.rpt w]
            puts $fd $text
            close $fd
            if {[regexp {slack[[:space:]]+\((MET|VIOLATED)\)[[:space:]]+([-+0-9.eE]+)} $text -> status slack]} {
                puts $summary "$domain $label slack: $slack ns ($status)"
            } else {
                puts $summary "$domain $label slack: NA (inspect report; not a pass)"
            }
            flush $summary
        }
    }
    close $summary
    redirect -file $directory/check_timing.rpt {check_timing}
    redirect -file $directory/clocks.rpt {report_clock -attributes}
    write_sdc $directory/constraints.sdc
    puts "Focused GPU check complete: $directory/summary.txt"
}
