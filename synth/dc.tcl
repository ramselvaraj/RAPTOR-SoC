# Run from any directory: dc_shell -f /path/to/RAPTOR-SoC/synth/dc.tcl
# TARGET_LIBRARY is a Tcl list of technology .db files (absolute paths).
# DC_MODE=core exposes the three large memories as ports instead of arrays.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]

proc env_or {name fallback} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $fallback
}

proc constraint_value {name fallback} {
    set value [env_or $name $fallback]
    if {![string is double -strict $value] || !($value >= 0 && $value < 1e9)} {
        error "$name must be a finite nonnegative number."
    }
    return $value
}

proc report_diagnostics {} {
    # Preserve the saved constraints. Do not change margins to hide violations.
    redirect -file reports/timing_hold.rpt {
        report_timing -delay_type min -max_paths 10 -significant_digits 6
    }
    redirect -file reports/constraints_detailed.rpt {
        report_constraint -all_violators -significant_digits 6
    }
    redirect -file reports/clock.rpt {report_clock -attributes}
    redirect -file reports/units.rpt {report_units}
    redirect -file reports/ports.rpt {report_port -verbose [get_ports *]}
    redirect -file reports/check_timing.rpt {check_timing}
    write_sdc results/constraints_diagnostic.sdc
}

proc run_synthesis {} {
    global repo_dir script_dir
    set top soc_top
    set mode [env_or DC_MODE soc]
    if {$mode ni {soc core phase5}} {
        error "DC_MODE must be soc, core, or phase5."
    }
    set defines [list SYNTHESIS]
    set default_output [file join $repo_dir synth build]
    if {$mode eq "core"} {
        lappend defines RAPTOR_EXTERNAL_MEMORIES
        set default_output [file join $default_output core]
    }
    set manifest_path [file join $repo_dir soc rtl files.txt]
    if {$mode eq "phase5"} {
        set top soc_phase5_top
        lappend defines RAPTOR_EXTERNAL_MEMORIES
        set default_output [file join $repo_dir synth build phase5]
        set manifest_path [file join $repo_dir soc phase5_files.txt]
    }
    set libraries [env_or TARGET_LIBRARY {}]
    if {[llength $libraries] == 0} {
        error "Set TARGET_LIBRARY to a Tcl list of absolute technology .db paths."
    }
    set extra_libraries [env_or LINK_LIBRARY {}]
    foreach library [concat $libraries $extra_libraries] {
        if {![file isfile $library] || [file pathtype $library] ne "absolute"} {
            error "Library must be an existing absolute path: $library"
        }
    }

    set output_dir [file normalize [env_or DC_OUT_DIR $default_output]]
    file mkdir $output_dir
    cd $output_dir
    file mkdir work reports results
    define_design_lib WORK -path [file join $output_dir work]

    set_app_var target_library $libraries
    # compile_ultra uses the installed DesignWare implementation of arithmetic.
    set_app_var synthetic_library [list dw_foundation.sldb]
    set_app_var link_library [concat [list *] $libraries $extra_libraries [list dw_foundation.sldb]]

    if {[env_or DC_PHASE5_GPU_CHECK 0] eq "1"} {
        if {$mode ne "phase5"} {error "DC_PHASE5_GPU_CHECK requires DC_MODE=phase5."}
        source [file join $script_dir phase5_gpu_check.tcl]
        run_phase5_gpu_check $repo_dir
        return
    }

    if {[env_or DC_PHASE5_CPU_CHECK 0] eq "1"} {
        if {$mode ne "phase5"} {error "DC_PHASE5_CPU_CHECK requires DC_MODE=phase5."}
        source [file join $script_dir phase5_constraints.tcl]
        source [file join $script_dir phase5_cpu_check.tcl]
        run_phase5_cpu_check
        return
    }

    if {[env_or DC_PHASE5_SWEEP 0] eq "1"} {
        if {$mode ne "phase5"} {error "DC_PHASE5_SWEEP requires DC_MODE=phase5."}
        source [file join $script_dir phase5_constraints.tcl]
        source [file join $script_dir phase5_sweep.tcl]
        run_phase5_sweep $script_dir
        return
    }

    if {[env_or DC_CONSTRAINT_SWEEP 0] eq "1"} {
        if {$mode eq "phase5"} {error "The legacy single-clock sweep does not apply to Phase 5."}
        source [file join $script_dir sweep.tcl]
        run_constraint_sweep $top $script_dir
        return
    }

    if {[env_or DC_REPORT_ONLY 0] eq "1"} {
        if {![file isfile results/${top}.ddc]} {
            error "No mapped DDC in $output_dir/results. Run synthesis first or set DC_OUT_DIR."
        }
        read_ddc results/${top}.ddc
        current_design $top
        if {![link]} {
            error "Cannot link the saved mapped design."
        }
        report_diagnostics
        puts "Diagnostic reports complete, without recompilation: $output_dir/reports"
        return
    }

    set fd [open $manifest_path r]
    set manifest [read $fd]
    close $fd
    set rtl_sources {}
    set memory_sources [list soc/rtl/shared_ram.sv soc/rtl/program_memory.sv \
        multi_cycle/rtl/instruction_memory.sv]
    foreach line [split $manifest "\n"] {
        set line [string trim $line]
        if {$line ne "" && ![string match "#*" $line]} {
            if {$mode ne "soc" && $line in $memory_sources} {
                continue
            }
            lappend rtl_sources [file join $repo_dir $line]
        }
    }

    set fd [open reports/scope.rpt w]
    puts $fd "Synthesis mode: $mode"
    if {$mode ne "soc"} {
        puts $fd "CPU, GPU, AXI, MMIO, and register files included."
        puts $fd "Shared RAM and CPU/GPU instruction memories excluded; interfaces exposed as ports."
        puts $fd "I/O delays are budgets, not characterized memory timing."
        puts $fd "Area excludes the three memories; timing is not complete-SoC timing."
        if {$mode eq "phase5"} {puts $fd "Two clock domains. FIFO/cache storage remains included. CDC constraints need mapped/physical review."}
    } else {
        puts $fd "Full SoC, including register-based memories."
    }
    close $fd
    puts "Synthesis mode: $mode"
    if {![analyze -format sverilog -define $defines $rtl_sources]} {
        error "RTL analysis failed."
    }
    elaborate $top
    current_design $top
    if {![link]} {
        error "Design linking failed. Check the libraries and unresolved references."
    }
    uniquify
    if {$mode eq "phase5"} {
        source [file join $script_dir phase5_constraints.tcl]
        apply_phase5_constraints
    } else {
        source [file join $script_dir constraints.tcl]
    }

    redirect -file reports/check_elaborated.rpt {set design_ok [check_design]}
    if {!$design_ok} {
        error "Elaborated design failed check_design. See reports/check_elaborated.rpt."
    }
    write -format ddc -hierarchy -output results/${top}_elaborated.ddc
    if {[env_or DC_ELAB_ONLY 0] eq "1"} {
        puts "Elaboration complete: $output_dir"
        return
    }

    # Keep hierarchy to make the first mapped design easier to inspect.
    if {![compile_ultra -no_autoungroup]} {
        error "Technology mapping failed."
    }
    redirect -file reports/check_mapped.rpt {set design_ok [check_design]}
    if {!$design_ok} {
        error "Mapped design failed check_design. See reports/check_mapped.rpt."
    }
    change_names -rules verilog -hierarchy
    write -format ddc -hierarchy -output results/${top}.ddc
    write -format verilog -hierarchy -output results/${top}.v
    write_sdc results/${top}.sdc
    redirect -file reports/area.rpt {report_area -hierarchy}
    redirect -file reports/timing.rpt {report_timing -delay_type max -max_paths 20}
    redirect -file reports/constraints.rpt {report_constraint -all_violators}
    redirect -file reports/qor.rpt {report_qor}
    redirect -file reports/resources.rpt {report_resources -hierarchy}
    report_diagnostics
    puts "Synthesis complete: $output_dir"
}

if {[catch {run_synthesis} message]} {
    puts stderr "ERROR: $message"
    exit 1
}
exit 0
