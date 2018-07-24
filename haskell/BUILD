load("//skylark:lint.bzl", "skylark_lint")
load(":private/dummy_linker_archive.bzl", "dummy_linker_archive")

dummy_linker_archive(
    name = "dummy_static_lib",
    visibility = ["//visibility:public"],
)

exports_files(
    glob(["*.bzl"]) + [
        "assets/ghci_script",
        "private/c2hs_wrapper.sh",
        "private/haddock_wrapper.sh",
    ],
)

py_binary(
    name = "ghci_repl_wrapper",
    srcs = ["private/ghci_repl_wrapper.py"],
    deps = ["@bazel_tools//tools/python/runfiles"],
    visibility = ["//visibility:public"],
)

skylark_lint()
