# Bash setup for the ADDV lab server, based on addv-labs/lab2/part1/env.cshrc.
# From the repository root: source synth/env.sh
# Existing environment settings take precedence. No SRAM library is needed.

export DC_HOME="${DC_HOME:-/usr/local2/synopsys/syn_2023.12-SP51}"
export PDK_DIR="${PDK_DIR:-/usr/local2/cadence/NCSU/SRC/FreePDK45}"
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-27020@enlicense5.eas.asu.edu}"
export LM_LICENSE_FILE="${LM_LICENSE_FILE:-$SNPSLMD_LICENSE_FILE}"
export TARGET_LIBRARY="${TARGET_LIBRARY:-$PDK_DIR/osu_soc/lib/files/gscl45nm.db}"
export DC_CLOCK_PERIOD="${DC_CLOCK_PERIOD:-20.0}"

# Repeated sourcing must not add duplicate PATH entries.
case ":${PATH:-}:" in
    *":${DC_HOME}/bin:"*) ;;
    *) export PATH="${DC_HOME}/bin${PATH:+:$PATH}" ;;
esac

if ! command -v dc_shell >/dev/null 2>&1; then
    printf '%s\n' "Warning: dc_shell is not on PATH. Check DC_HOME on the lab server." >&2
fi
