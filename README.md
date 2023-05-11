# buck2-go

Buck2 build rules for Go

## Why?

This repository aims to be the equivalent of [bazelbuild/rules_go](https://github.com/bazelbuild/rules_go) for Buck2 ecosystem.
The eventual goal is to merge most of these rules back into Buck2 prelude.

Buck2 does come with some basic Go build rules under `prelude//go/...`, however they don't work outside of Meta (i.e. there is no stdlib to compile against).
It seems like the Go rules in Buck2 are also not maintained by anyone currently within Meta.
For faster iteration, let's work from a separate repo(this one) for the time being.

## Roadmap:

- [ ] Remote Go Toolchain
  + [X] Fetch toolchain
  + [ ] Export sub targets

- [ ] Build Stdlib

- [X] Build `go_bootstrap_binary` (same as `go_tool_binary` in Bazel)
  + [ ] Implement `builder` binary

- [ ] Write Go Context

- [ ] Write actions using `builder` binary
  + [ ] compilepkg
  + [ ] link
  + [ ] pack
  + [ ] archive
  + [ ] generate test source

- [ ] Write rules using actions
  + [ ] binary
  + [ ] test internal
  + [ ] test external

- [ ] Support 3rd party libraries

- [ ] Support CGO

- [ ] BXL
  + [ ] Go Package Driver + gopls
  + [ ] Linter

- [ ] Seperate host/exec/target platforms (transition?)

## Open questions

1. Do we copy the code from rules_go or try to manage rules_go using http_archive?

2. Extends Gazelle or write something new to support Buck2? (there is no repository loading phase)
