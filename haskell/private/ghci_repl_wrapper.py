#!/usr/bin/env python
#
# Usage: ghci_repl_wrapper.py <ARGS>

from bazel_tools.tools.python.runfiles import runfiles

print("hello python")
r = runfiles.Create()
for f in r._strategy._runfiles:
    print(f)

# TODO: this {GHCi} should be replaced by the template mechanism
print("GHCi location: " + r.Rlocation("{GHCi}"))

