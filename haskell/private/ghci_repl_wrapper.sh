#!/usr/bin/env bash
#
# Usage: ghci_repl_wrapper.sh <ARGS>

export LD_LIBRARY_PATH={LDLIBPATH}
"{GHCi}" {ARGS} "$@"
