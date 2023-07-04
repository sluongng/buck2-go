load("@prelude//http_archive/exec_deps.bzl", "HttpArchiveExecDeps")
load("@prelude//cxx:cxx_toolchain_types.bzl", "CxxToolchainInfo")
load("@prelude//decls/common.bzl", "buck")
load("@prelude//go:toolchain.bzl", "GoToolchainInfo")
load("@prelude//os_lookup:defs.bzl", "OsLookup")
load("@prelude//:prelude.bzl", "native")
load(":go_toolchain_release.bzl", "GO_SDKS_METADATA")

def _get_go_arch() -> "string":
    arch = host_info().arch
    if arch.is_aarch64:
        return "arm64"
    elif arch.is_x86_64:
        return "amd64"
    else:
        fail("Unsupported go arch: {}".format(arch))

def _get_go_os() -> "string":
    os = host_info().os
    if os.is_macos:
        return "darwin"
    elif os.is_linux:
        return "linux"
    else:
        fail("Unsupported go os: {}".format(os))

def _go_tool_path(go_os: "string", go_arch: "string", go_tool: "string") -> "string":
    return "pkg/tool/{}_{}/{}".format(go_os, go_arch, go_tool)

def _system_go_toolchain_impl(ctx: "context") -> ["provider"]:
    exec_os = ctx.attrs._exec_os_type[OsLookup]
    go_arch = "amd64" if exec_os.cpu == "x86_64" else exec_os.cpu
    go_os = exec_os.platform

    go_root = ctx.attrs.go_root

    go_binary = go_root + "/bin/go"
    srcs = go_root + "/src"
    headers = go_root + "/pkg/include"
    tools = go_root + "/pkg/tool"

    get_go_tool = lambda go_tool: "{}/{}".format(go_root, _go_tool_path(go_os, go_arch, go_tool))
    runner = cmd_args([go_binary])
    return [
        DefaultInfo(),
        RunInfo(args = runner),
        GoToolchainInfo(
            # Go binary
            go = go_binary,
            sdk_srcs = srcs,
            sdk_headers = headers,
            sdk_tools = tools,
            # Go env
            env_go_arch = go_arch,
            env_go_os = go_os,
            env_go_root = go_root,
            env_go_arm = None,
            # Go tools
            compiler = get_go_tool("compile"),
            compiler_flags_shared = "",
            compiler_flags_static = "",
            linker = get_go_tool("link"),
            linker_flags_shared = "",
            linker_flags_static = "",
            assembler = get_go_tool("asm"),
            cover = get_go_tool("cover"),
            packer = get_go_tool("pack"),
            # Helpers
            compile_wrapper = ctx.attrs.compile_wrapper,
            cover_srcs = ctx.attrs.cover_srcs,
            filter_srcs = ctx.attrs.filter_srcs,
            # CGO
            cgo = get_go_tool("cgo"),
            cgo_wrapper = ctx.attrs.cgo_wrapper,
            cxx_toolchain_for_linking = ctx.attrs.cxx_toolchain,
            external_linker_flags = ctx.attrs.external_linker_flags,
            # Go build tag
            tags = [],
        ),
    ]

system_go_toolchain = rule(
    impl = _system_go_toolchain_impl,
    doc = """System go toolchain rules. Usage:
  system_go_toolchain(
      name = "go",
      go_root = "/opt/homebrew/Cellar/go/1.20.4/libexec",
      visibility = ["PUBLIC"],
  )""",
    attrs = {
        "go_root": attrs.string(),
        "cxx_toolchain": attrs.option(attrs.dep(providers = [CxxToolchainInfo]), default = None),
        "external_linker_flags": attrs.list(attrs.string(), default = []),
        "cgo_wrapper": attrs.default_only(attrs.dep(providers = [RunInfo], default = "prelude//go/tools:cgo_wrapper")),
        "compile_wrapper": attrs.default_only(attrs.dep(providers = [RunInfo], default = "prelude//go/tools:compile_wrapper")),
        "cover_srcs": attrs.default_only(attrs.dep(providers = [RunInfo], default = "prelude//go/tools:cover_srcs")),
        "filter_srcs": attrs.default_only(attrs.dep(providers = [RunInfo], default = "prelude//go/tools:filter_srcs")),
        "_exec_os_type": buck.exec_os_type_arg(),
    },
    is_toolchain_rule = True,
)

def _remote_go_toolchain_impl(ctx) -> ["promise", ["provider"]]:
    exec_os = ctx.attrs._exec_os_type[OsLookup]
    go_arch = "amd64" if exec_os.cpu == "x86_64" else exec_os.cpu
    go_os = exec_os.platform

    expected_version = "go" + ctx.attrs.version
    sdk_metadata = None
    for current in GO_SDKS_METADATA:
        if current["version"] == expected_version:
            sdk_metadata = current
            break
    if not sdk_metadata:
        fail("Unsupported go version: {}".format(ctx.attr.version))

    sdk_file_metadata = None
    for file_metadata in sdk_metadata["files"]:
        if file_metadata["os"] == go_os and file_metadata["arch"] == go_arch and file_metadata["kind"] == "archive":
            sdk_file_metadata = file_metadata
            break
    if not sdk_file_metadata:
        fail("Could not find suitable download ({}, {}) for go version: {}".format(go_os, go_arch, ctx.attrs.version))

    def handle_toolchain_archive(providers: "provider_collection") -> ["provider"]:
        go_root = providers[DefaultInfo].default_outputs[0]
        archive_sub_targets = providers[DefaultInfo].sub_targets

        go_binary = archive_sub_targets["bin/go"][DefaultInfo].default_outputs[0]
        tools = archive_sub_targets["pkg/tool"][DefaultInfo].default_outputs[0]
        srcs = archive_sub_targets["src"][DefaultInfo].default_outputs[0]
        headers = archive_sub_targets["pkg/include"][DefaultInfo].default_outputs[0]

        get_go_tool = lambda go_tool: archive_sub_targets[_go_tool_path(go_os, go_arch, go_tool)][DefaultInfo].default_outputs[0]

        runner = cmd_args([go_binary])
        return [
            DefaultInfo(),
            RunInfo(args = runner),
            GoToolchainInfo(
                # Go binary
                go = go_binary,
                sdk_srcs = srcs,
                sdk_headers = headers,
                sdk_tools = tools,
                # Go env
                env_go_arch = go_arch,
                env_go_os = go_os,
                env_go_root = go_root,
                env_go_arm = None,
                # Go tools
                compiler = get_go_tool("compile"),
                compiler_flags_shared = "",
                compiler_flags_static = "",
                linker = get_go_tool("link"),
                linker_flags_shared = "",
                linker_flags_static = "",
                assembler = get_go_tool("asm"),
                cover = get_go_tool("cover"),
                packer = get_go_tool("pack"),
                # Helpers
                compile_wrapper = ctx.attrs.compile_wrapper,
                cover_srcs = ctx.attrs.cover_srcs,
                filter_srcs = ctx.attrs.filter_srcs,
                # CGO
                cgo = get_go_tool("cgo"),
                cgo_wrapper = ctx.attrs.cgo_wrapper,
                cxx_toolchain_for_linking = ctx.attrs.cxx_toolchain,
                external_linker_flags = ctx.attrs.external_linker_flags,
                # Go build tag
                tags = [],
            ),
        ]

    return ctx.actions.anon_target(native.http_archive, {
        "exec_deps": ctx.attrs._http_archive_exec_deps,
        "urls": ["https://dl.google.com/go/{}".format(sdk_file_metadata["filename"])],
        "sha256": sdk_file_metadata["sha256"],
        "sub_targets": [
            _go_tool_path(go_os, go_arch, go_tool)
            for go_tool in [
                "asm",
                "cgo",
                "compile",
                "cover",
                "link",
                "pack",
            ]
        ] + ["bin/go", "pkg/include", "pkg/tool", "src"],
        "strip_prefix": "go",
    }).map(handle_toolchain_archive)

remote_go_toolchain = rule(
    impl = _remote_go_toolchain_impl,
    doc = """Remote go toolchain rules. Usage:
  remote_go_toolchain(
      name = "go",
      go_version = "1.20.4",
      visibility = ["PUBLIC"],
  )""",
    attrs = {
        "version": attrs.string(doc = "Go version, example: '1.20.4'"),
        "cxx_toolchain": attrs.option(attrs.dep(providers = [CxxToolchainInfo]), default = None),
        "external_linker_flags": attrs.list(attrs.string(), default = []),
        "cgo_wrapper": attrs.default_only(attrs.dep(providers = [RunInfo], default = "prelude//go/tools:cgo_wrapper")),
        "compile_wrapper": attrs.default_only(attrs.dep(providers = [RunInfo], default = "prelude//go/tools:compile_wrapper")),
        "cover_srcs": attrs.default_only(attrs.dep(providers = [RunInfo], default = "prelude//go/tools:cover_srcs")),
        "filter_srcs": attrs.default_only(attrs.dep(providers = [RunInfo], default = "prelude//go/tools:filter_srcs")),
        "_http_archive_exec_deps": attrs.default_only(attrs.dep(providers = [HttpArchiveExecDeps], default = "prelude//http_archive/tools:exec_deps")),
        "_exec_os_type": buck.exec_os_type_arg(),
    },
    is_toolchain_rule = True,
)
