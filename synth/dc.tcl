# Run from any directory: dc_shell -f /path/to/RAPTOR-SoC/synth/dc.tcl
# TARGET_LIBRARY is a Tcl list of technology .db files (absolute paths).

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]

proc env_or {name fallback} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $fallback
}

proc run_synthesis {} {
    global repo_dir script_dir
    set top soc_top
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

    set output_dir [file normalize [env_or DC_OUT_DIR [file join $repo_dir synth build]]]
    file mkdir $output_dir
    cd $output_dir
    file mkdir work reports results
    define_design_lib WORK -path [file join $output_dir work]

    set_app_var target_library $libraries
    # compile_ultra uses the installed DesignWare implementation of arithmetic.
    set_app_var synthetic_library [list dw_foundation.sldb]
    set_app_var link_library [concat [list *] $libraries $extra_libraries [list dw_foundation.sldb]]

    set fd [open [file join $repo_dir soc rtl files.txt] r]
    set manifest [read $fd]
    close $fd
    set rtl_sources {}
    foreach line [split $manifest "\n"] {
        set line [string trim $line]
        if {$line ne "" && ![string match "#*" $line]} {
            lappend rtl_sources [file join $repo_dir $line]
        }
    }

    if {![analyze -format sverilog -define SYNTHESIS $rtl_sources]} {
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
    puts "Synthesis complete: $output_dir"
}

if {[catch {run_synthesis} message]} {
    puts stderr "ERROR: $message"
    exit 1
}
exit 0
