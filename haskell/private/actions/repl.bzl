"""GHCi REPL support"""

load(
    "@bazel_skylib//:lib.bzl",
    "paths",
    "shell",
)
load(
    ":private/providers.bzl",
    "HaskellBinaryInfo",
    "HaskellBuildInfo",
    "HaskellLibraryInfo",
)
load(
    ":private/path_utils.bzl",
    "get_external_libs_path",
    "get_lib_name",
    "ln",
    "target_unique_name",
)
load(
    ":private/set.bzl",
    "set",
)

def build_haskell_repl(
        hs,
        ghci_script,
        compiler_flags,
        repl_ghci_args,
        build_info,
        output,
        lib_info = None,
        bin_info = None):
    """Build REPL script.

    Args:
      hs: Haskell context.
      build_info: HaskellBuildInfo.

      lib_info: If we're building REPL for a library target, pass
                HaskellLibraryInfo here, otherwise it should be None.
      bin_info: If we're building REPL for a binary target, pass
                HaskellBinaryInfo here, otherwise it should be None.

    Returns:
      None.
    """

    # Bring packages in scope.
    args = ["-hide-all-packages"]
    for dep in set.to_list(build_info.prebuilt_dependencies):
        args += ["-package ", dep]
    for package in set.to_list(build_info.package_ids):
        if not (lib_info != None and package == lib_info.package_id):
            args += ["-package-id", package]
    for cache in set.to_list(build_info.package_caches):
        args += ["-package-db", cache.dirname]

    if lib_info != None:
        for idir in set.to_list(lib_info.import_dirs):
            args += ["-i{0}".format(idir)]

    # External libraries.
    seen_libs = set.empty()
    for lib in build_info.external_libraries.values():
        lib_name = get_lib_name(lib)
        if not set.is_member(seen_libs, lib_name):
            set.mutable_insert(seen_libs, lib_name)
            args += ["-l{0}".format(lib_name)]

    ghci_repl_script = hs.actions.declare_file(target_unique_name(hs, "ghci-repl-script"))

    add_modules = []
    if lib_info != None:
        # If we have a library, we put names of its exposed modules here.
        add_modules = set.to_list(
            lib_info.exposed_modules,
        )
    elif bin_info != None:
        # Otherwise we put paths to module files, mostly because it also works
        # and Main module may be in a file with name that's impossible for GHC
        # to infer.
        add_modules = [f.path for f in set.to_list(bin_info.source_files)]

    visible_modules = []
    if lib_info != None:
        # If we have a library, we put names of its exposed modules here.
        visible_modules = set.to_list(lib_info.exposed_modules)
    elif bin_info != None:
        # Otherwise we do rougly the same by using modules from
        # HaskellBinaryInfo.
        visible_modules = set.to_list(bin_info.modules)

    hs.actions.expand_template(
        template = ghci_script,
        output = ghci_repl_script,
        substitutions = {
            "{ADD_MODULES}": " ".join(add_modules),
            "{VISIBLE_MODULES}": " ".join(visible_modules),
        },
    )

    source_files = lib_info.source_files if lib_info != None else bin_info.source_files

    args += ["-ghci-script", ghci_repl_script.path]

    # Extra arguments.
    # `compiler flags` is the default set of arguments for the repl,
    # augmented by `repl_ghci_args`.
    # The ordering is important, first compiler flags (from toolchain
    # and local rule), then from `repl_ghci_args`. This way the more
    # specific arguments are listed last, and then have more priority in
    # GHC.
    # Note that most flags for GHCI do have their negative value, so a
    # negative flag in `repl_ghci_args` can disable a positive flag set
    # in `compiler_flags`, such as `-XNoOverloadedStrings` will disable
    # `-XOverloadedStrings`.
    args += hs.toolchain.compiler_flags + compiler_flags + hs.toolchain.repl_ghci_args + repl_ghci_args

    # hs.actions.expand_template(
    #     template = ghci_repl_wrapper,
    #     output = repl_file,
    #     substitutions = {
    #         "{LDLIBPATH}": get_external_libs_path(
    #             set.union(
    #                 build_info.dynamic_libraries,
    #                 set.from_list(build_info.external_libraries.values()),
    #             ),
    #             prefix = "$RULES_HASKELL_EXEC_ROOT",
    #         ),
    #         "{GHCi}": hs.tools.ghci.short_path,
    #         "{SCRIPT_LOCATION}": output.path,
    #         "{ARGS}": 
    #     },
    #     is_executable = True,
    # )

    # XXX We create a symlink here because we need to force
    # hs.tools.ghci and ghci_script and the best way to do that is
    # to use hs.actions.run. That action, it turn must produce
    # a result, so using ln seems to be the only sane choice.
    # extra_inputs = depset(transitive = [
    #     depset([
    #         hs.tools.ghci,
    #         ghci_repl_script,
    #         repl_file,
    #     ]),
    #     set.to_depset(build_info.package_caches),
    #     depset(build_info.external_libraries.values()),
    #     set.to_depset(source_files),
    # ])
    # ln(hs, repl_file, output, extra_inputs)

    # TODO: Use the repl wrapper, silly
    # TODO: add runfiles to this rule (maybe?)
    # TODO: munge into a template again, maybe?
    hs.actions.write(
        output,
        is_executable=True,
        content = """#!/usr/bin/env bash
# TODO: this is a big pile of shit, replace once runfiles support is better
# --- begin runfiles.bash initialization ---
set -euo pipefail
echo \$0 IS: $0
echo \$0 W/O suffix is: ${0%-repl}
if [[ ! -d "${RUNFILES_DIR:-/dev/null}" && ! -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  if [[ -f "${0%-repl}.runfiles_manifest" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
  elif [[ -f "${0%-repl}.runfiles/MANIFEST" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
  elif [[ -f "${0%-repl}.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
    export RUNFILES_DIR="$0.runfiles"
  fi
fi
if [[ -f "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
  source "${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  source "$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " \
            "$RUNFILES_MANIFEST_FILE" | cut -d ' ' -f 2-)"
else
  find ${0%-repl}.runfiles
  echo >&2 "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash"
  exit 1
fi
# --- end runfiles.bash initialization ---
""" + """
cat "$(rlocation foobar)
""".format(
            # This conversion to a python list of strings is based
            # on the assumption that bazel strings & repr() follow the same
            # semantics as python strings & repr() (if bazel is a true
            # subset of python that should hold).
            # py_arglist = repr([shell.quote(a) for a in args]),
        ),
    )
