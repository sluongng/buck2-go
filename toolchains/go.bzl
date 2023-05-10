load("@prelude//cxx:cxx_toolchain_types.bzl", "CxxToolchainInfo")
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
    go_root = ctx.attrs.go_root
    go_binary = go_root + "/bin/go"

    go_arch = _get_go_arch()
    go_os = _get_go_os()

    get_go_tool = lambda go_tool: "{}/{}".format(go_root, _go_tool_path(go_os, go_arch, go_tool))
    runner = cmd_args([go_binary])
    return [
        DefaultInfo(),
        RunInfo(args = runner),
        GoToolchainInfo(
            # Go binary
            go = go_binary,
            # Go env
            env_go_arch = go_arch,
            env_go_os = go_os,
            env_go_root = go_root,
            # Go tools
            assembler = get_go_tool("asm"),
            cgo = get_go_tool("cgo"),
            compiler = get_go_tool("compile"),
            cover = get_go_tool("cover"),
            linker = get_go_tool("link"),
            packer = get_go_tool("pack"),
            # Helpers
            compile_wrapper = ctx.attrs.compile_wrapper,
            cover_srcs = ctx.attrs.cover_srcs,
            filter_srcs = ctx.attrs.filter_srcs,
            # CGO
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
    },
    is_toolchain_rule = True,
)

def _remote_go_toolchain_impl(ctx) -> ["promise", ["provider"]]:
    go_arch = _get_go_arch()
    go_os = _get_go_os()

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
        fail("Could not find suitable download for go version: {}".format(ctx.attr.version))

    def handle_toolchain_archive(providers: "provider_collection") -> ["provider"]:
        go_root = providers[DefaultInfo].default_outputs[0]
        archive_sub_targets = providers[DefaultInfo].sub_targets

        go_binary = archive_sub_targets["bin/go"][DefaultInfo].default_outputs[0]
        get_go_tool = lambda go_tool: archive_sub_targets[_go_tool_path(go_os, go_arch, go_tool)][DefaultInfo].default_outputs[0]
        runner = cmd_args([go_binary])
        return [
            DefaultInfo(),
            RunInfo(args = runner),
            GoToolchainInfo(
                # Go binary
                go = go_binary,
                # Go env
                env_go_arch = go_arch,
                env_go_os = go_os,
                env_go_root = go_root,
                # Go tools
                assembler = get_go_tool("asm"),
                cgo = get_go_tool("cgo"),
                compiler = get_go_tool("compile"),
                cover = get_go_tool("cover"),
                linker = get_go_tool("link"),
                packer = get_go_tool("pack"),
                # Helpers
                compile_wrapper = ctx.attrs.compile_wrapper,
                cover_srcs = ctx.attrs.cover_srcs,
                filter_srcs = ctx.attrs.filter_srcs,
                # CGO
                cgo_wrapper = ctx.attrs.cgo_wrapper,
                cxx_toolchain_for_linking = ctx.attrs.cxx_toolchain,
                external_linker_flags = ctx.attrs.external_linker_flags,
                # Go build tag
                tags = [],
            ),
        ]

    return ctx.actions.anon_target(native.http_archive, {
        "urls": ["https://dl.google.com/go/{}".format(sdk_file_metadata["filename"])],
        "sha256": sdk_file_metadata["sha256"],
        "sub_targets": ["bin/go"] + [
            _go_tool_path(go_os, go_arch, go_tool)
            for go_tool in [
                "asm",
                "cgo",
                "compile",
                "cover",
                "link",
                "pack",
            ]
        ],
        "strip_prefix": "go",
        # Anon target hacks
        # See https://github.com/facebook/buck2/commit/76e9a01ade4b91a95be961e75dad287bc99f81c4
        "_create_exclusion_list": [],
        "_exec_os_type": [],
        "_override_exec_platform_name": ctx.attrs._exec_os_type[OsLookup].platform,
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
        "_exec_os_type": attrs.default_only(attrs.exec_dep(default = "prelude//os_lookup/targets:os_lookup")),
    },
    is_toolchain_rule = True,
)
