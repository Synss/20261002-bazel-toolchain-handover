# Bazel CC toolchain handover

Slides for handing over the Bazel CC toolchain.

Presentation given at Checkmk, 2026-10-02.

**[Open slides](https://synss.github.io/20261002-bazel-toolchain-handover/)**

## Build

- Nix with flakes enabled
- direnv, or run commands through `nix develop`
- just

```sh
direnv allow   # once; or prefix commands with `nix develop -c`
just
```

This writes `build/slides.html`: a self-contained reveal.js deck. Building
needs network access; presenting doesn't.
