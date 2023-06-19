load("@prelude//decls:go_common.bzl", "go_common")
load("@prelude//decls/toolchains_common.bzl", "toolchains_common")
load("@prelude//go:toolchain.bzl", "GoToolchainInfo", "get_toolchain_cmd_args")

def go_bootstrap_binary_impl(ctx: "context") -> ["provider"]:
    go_toolchain = ctx.attrs._go_toolchain[GoToolchainInfo]
    out = ctx.actions.declare_output("main")
    gocache = ctx.actions.declare_output("gocache", dir = True)

    build_script = ctx.actions.write(
        "build.sh",
        [
            cmd_args(go_toolchain.go, format = 'export GOROOT="${PWD}/$(dirname $(dirname {}))"'),
            cmd_args(["export", "GOPATH=$(mktemp -d)"]),
            cmd_args(gocache.as_output(), format = 'export GOCACHE="${PWD}/{}"'),
            cmd_args(["mkdir", "-p", "$GOCACHE"], delimiter = " "),
            cmd_args([go_toolchain.go, "build", "-o", out.as_output(), "-trimpath"] + ctx.attrs.srcs, delimiter = " "),
        ],
        is_executable = True,
    )

    ctx.actions.run(
        cmd_args(["/bin/sh", build_script]).hidden(
            gocache.as_output(),
            go_toolchain.go,
            out.as_output(),
            ctx.attrs.srcs,
            go_toolchain.sdk_srcs,
            go_toolchain.sdk_headers,
            go_toolchain.sdk_tools,
        ),
        category = "go_tool_binary",
        no_outputs_cleanup = True,  # Preserve GOCACHE for subsequent runs
    )

    return [
        DefaultInfo(default_output = out),
        RunInfo(args = cmd_args(out)),
    ]

go_bootstrap_binary = rule(
    impl = go_bootstrap_binary_impl,
    attrs = {
        "_go_toolchain": toolchains_common.go(),
    } | go_common.srcs_arg(),
)
