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
    redirect -file reports/check_timing.rpt {check_timing -verbose}
    write_sdc results/constraints_diagnostic.sdc
}

proc run_synthesis {} {
    global repo_dir script_dir
    set top soc_top
    set mode [env_or DC_MODE soc]
    if {$mode ni {soc core}} {
        error "DC_MODE must be soc or core."
    }
    set defines [list SYNTHESIS]
    set default_output [file join $repo_dir synth build]
    if {$mode eq "core"} {
        lappend defines RAPTOR_EXTERNAL_MEMORIES
        set default_output [file join $default_output core]
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

    if {[env_or DC_REPORT_ONLY 0] eq "1"} {
        if {![file isfile results/soc_top.ddc]} {
            error "No mapped DDC in $output_dir/results. Run synthesis first or set DC_OUT_DIR."
        }
        read_ddc results/soc_top.ddc
        current_design $top
        if {![link]} {
            error "Cannot link the saved mapped design."
        }
        report_diagnostics
        puts "Diagnostic reports complete, without recompilation: $output_dir/reports"
        return
    }

    set fd [open [file join $repo_dir soc rtl files.txt] r]
    set manifest [read $fd]
    close $fd
    set rtl_sources {}
    set memory_sources [list soc/rtl/shared_ram.sv soc/rtl/program_memory.sv \
        multi_cycle/rtl/instruction_memory.sv]
    foreach line [split $manifest "\n"] {
        set line [string trim $line]
        if {$line ne "" && ![string match "#*" $line]} {
            if {$mode eq "core" && $line in $memory_sources} {
                continue
            }
            lappend rtl_sources [file join $repo_dir $line]
        }
    }

    set fd [open reports/scope.rpt w]
    puts $fd "Synthesis mode: $mode"
    if {$mode eq "core"} {
        puts $fd "CPU, GPU, AXI, MMIO, and register files included."
        puts $fd "Shared RAM and CPU/GPU instruction memories excluded; interfaces exposed as ports."
        puts $fd "I/O delays are budgets, not characterized memory timing."
        puts $fd "Area excludes the three memories; timing is not complete-SoC timing."
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
    source [file join $script_dir constraints.tcl]

    redirect -file reports/check_elaborated.rpt {set design_ok [check_design]}
    if {!$design_ok} {
        error "Elaborated design failed check_design. See reports/check_elaborated.rpt."
    }
    write -format ddc -hierarchy -output results/soc_top_elaborated.ddc
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
    write -format ddc -hierarchy -output results/soc_top.ddc
    write -format verilog -hierarchy -output results/soc_top.v
    write_sdc results/soc_top.sdc
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
