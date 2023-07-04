def _re_platform_impl(ctx):
    constraints = dict()
    constraints.update(ctx.attrs._os_configuration[ConfigurationInfo].constraints)
    constraints.update(ctx.attrs._arch_configuration[ConfigurationInfo].constraints)

    return [
        DefaultInfo(),
        ExecutionPlatformRegistrationInfo(
            platforms = [ExecutionPlatformInfo(
                label = ctx.label.raw_target(),
                configuration = ConfigurationInfo(
                    constraints = constraints,
                    values = {},
                ),
                executor_config = CommandExecutorConfig(
                    local_enabled = False,
                    remote_enabled = True,
                    use_limited_hybrid = False,
                    remote_execution_properties = {
                        "recycle-runner": "true",
                    },
                    remote_execution_use_case = "buck2-default",
                    remote_output_paths = "output_paths",
                ),
            )],
        ),
    ]

re_platform = rule(
    impl = _re_platform_impl,
    attrs = {
        "_os_configuration": attrs.dep(providers = [ConfigurationInfo], default = "prelude//os:linux"),
        "_arch_configuration": attrs.dep(providers = [ConfigurationInfo], default = "prelude//cpu:x86_64"),
    },
)
