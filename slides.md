---
# pagetitle instead of title: pandoc adds no separate title slide.
pagetitle: "Bazel CC toolchain handover"
slideNumber: true
transition: none
center: false
width: 1280
height: 720
margin: 0.02
---

## Bazel CC toolchain handover

::: {.section-details}
- Presenter: Mathias Laurin
- Date: 2026-11-02
- Handed over to: -REDACTED-
:::

::: {.section-toc}

### Agenda

- Toolchains
  - Toolchain layers
  - Toolchain generation
  - Our toolchains

- Bazel
  - Platforms and toolchain resolution
  - Wrappers for transitions

- Debugging
  - Our toolchain
  - Inspect configuration
  - Inspect actions
  - Inspect binary artifacts

- Handover
  - Pitfalls
  - Open issues

:::

## Toolchains: Toolchain layers

::: {.columns}
:::: {.column}

![](diagrams/layers.svg){height=300px}

- C++ library -- libstdc++
- C library -- glibc: C standard library and system call wrappers
- Kernel -- Linux headers: kernel/user-space API

:::::: {.callout-info}
Built against old glibc runs on newer glibc:  
glibc is backward compatible.
::::::

::::
:::: {.column}

### Requirements

| build  | host     | target   |
| ------ | -------- | -------- |
| Docker image<br>(Ubuntu 24.04) | Almalinux 8, 9, 10<br>Debian 12, 13<br>SLES 15SP7, 16<br>Ubuntu 22.04, 24.04, 26.04 | Almalinux 8, ... <br>Debian, SLES, Ubuntu ...<br>(same list of distros) |

All x86_64, **but** glibc versions differ:

| Distro       | glibc | kernel-headers |
| ------------ | ------| -------------- |
| Almalinux 8  | 2.28  | 4.18 |
| Ubuntu 24.04 | 2.39  | 6.8  |

Cross-compilation with: build ≠ host = target

:::::: {.callout-info}
*Goal of hermetic toolchain:*

- build every artifact with the oldest glibc to produce binaries that run on every distro.
build ≟ host ≠ target
- libstdc++ is linked statically in some binaries and shipped as a shared library otherwise.
::::::
::::
:::

## Toolchains: Toolchain generation

::: {.columns}
:::: {.column}

```
buildscripts/scripts/gcc-toolchain
├── build.sh
├── common.sh
├── docker
│   ├── build.sh
│   ├── Dockerfile
│   └── test.sh
├── README.md
├── test.sh
├── upload.sh
└── x86_64-checkmk-linux-gnu.defconfig
```

- `README.md`: context and instructions
- `build.sh`: entry point
- `test.sh`: smoke tests for the generated toolchain
- `upload.sh`: make toolchain available on AWS (world readable)  
  ⇒ requires credentials available in Jenkins
- `docker/Dockerfile`: toolchain build environment
- `x86_64-checkmk-linux-gnu.defconfig`: crosstool-NG config

:::::: {.callout-info}
Crosstool-NG is a menuconfig-based toolchain generator,
[https://crosstool-ng.github.io/](https://crosstool-ng.github.io/)
::::::

::::
:::: {.column}

`x86_64-checkmk-linux-gnu.defconfig`

```text
CT_CONFIG_VERSION="4"
CT_OBSOLETE=y
CT_ARCH_X86=y
CT_ARCH_64=y
CT_TARGET_VENDOR="checkmk"
CT_KERNEL_LINUX=y
CT_LINUX_V_4_18=y
# CT_KERNEL_LINUX_INSTALL_CHECK is not set
CT_BINUTILS_V_2_45=y
CT_GLIBC_V_2_28=y
CT_GCC_V_14=y
CT_CC_LANG_CXX=y
CT_DEBUG_GDB=y
CT_GDB_CROSS_STATIC=y
CT_STATIC_TOOLCHAIN=y
```

- `CT_LINUX_V_4_18=y`: kernel version
- `CT_BINUTILS_V_2_45=y`: `ar`, `as`, `ld`, ... aim for the most recent
  possible  
  **⇒ update from time to time**
- `CT_GLIBC_V_2_28=y`: oldest glibc among supported distros (now Almalinux 8)  
  **⇒ update when we drop that distro**
- `CT_DEBUG_GDB=y` and `CT_GDB_CROSS_STATIC=y`: static `gdb` that runs on any
  machine, **to debug core dumps**
- `CT_STATIC_TOOLCHAIN=y`: statically linked `gcc`, `ld`, ...  runs on any
  machine, not only in the Docker image that built it  
  **⇒ drop if the toolchain only runs where it is built**

::::
:::

## Toolchains: Our toolchains

::: {.columns}
:::: {.column}

### Hermetic toolchain

- Artifact: `AWS:.../x86_64-checkmk-linux-gnu-gcc14.4.0-glibc2.28.tar.xz`
- Bazel repository: `bazel/thirdparty/modules/gcc_toolchain/`
- Toolchain declaration: `bazel/toolchains/cc/gcc/hermetic/**`
- Bazel API: Rules-based API

### Local toolchains

- Artifact: local (host, default), differs in CI vs dev computer
- Toolchain declaration: `bazel/toolchains/cc/gcc/local/BUILD`
- Bazel API: Legacy `cc_common.create_cc_toolchain_config_info`

### LLVM toolchain

- Provides clang-tidy hermetically
- Clang built-in headers (`stddef.h`, intrinsics):
  `bazel/thirdparty/modules/clang-resource-headers`
- Prebuilt binary: `rules_multitool` lockfile `bazel/tools/multitool.lock.json`
- Toolchain declaration: none, not used for compilation
- Bazel integration: `rules_lint` aspect (`lint_clang_tidy_aspect()`)

::::
:::: {.column}

### Consumers

![](diagrams/consumers.svg){height=250px}

The hermetic toolchain has three consumers:

- `rules_cc`: native, Bazel is the build system
- `foreign_cc`: foreign, delegates to another build system
- clang-tidy: LLVM-based linter

:::::: {.callout-info}
All three consumers must be tested after changes to the toolchains.
::::::

::::
:::

## Bazel: Platforms and toolchain resolution

::: {.columns totalwidth="100%"}
:::: {.column width="45%"}

![](diagrams/resolution.svg){height=180px}

- Exec and target: `@platforms//os:linux` and `@platforms//cpu:x86_64`
- The hermetic toolchain also requires the `:hermetic` constraint value
- Setting the target platform selects the toolchain:
  `--platforms` or the wrappers (next slide)

:::::: {.callout-seealso}
- [bazel:concepts/platforms](https://bazel.build/concepts/platforms)
- [bazel:ref/platforms-and-toolchains](https://bazel.build/reference/be/platforms-and-toolchains)
::::::

::::
:::: {.column}

`bazel/platforms/BUILD` (visibility omitted)

```python
platform(
    name = "x86_64-linux-gcc-hermetic",
    constraint_values = [
        ":hermetic",
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
)

constraint_setting(
    name = "hermeticity",
    default_constraint_value = ":hermeticity_unknown",
)

constraint_value(name = "hermetic", constraint_setting = ":hermeticity")
constraint_value(name = "hermeticity_unknown", constraint_setting = ":hermeticity")

# For select()
config_setting(name = "is_hermetic", constraint_values = [":hermetic"])
```

#### Nomenclature

| GNU (compiler) | Bazel | Our case |
| --- | --- | --- |
| build | none (crosstool-NG's concern) | the Docker image |
| host | exec | every distro |
| target | target | the same distros |

::::
:::


## Bazel: Wrappers for transitions

- Public API: `bazel/rules/xcomp/cc.bzl`
- Implementation: `bazel/rules/private/xcomp/**`

The wrappers add a `platform` attribute to `cc_{binary,library,test}`.  It
applies a transition that sets the target platform (`--platforms`) for the
target and its deps.  No-op if `platform` is unset.

Example:

```python
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")  # <-- upstream

cc_binary(
    name = "unixcat",
    srcs = ["src/unixcat.cc"],
    visibility = ["//visibility:public"],
    deps = ["//packages/livestatus:livestatus_poller"],
)
```

```python
load("//bazel/rules:xcomp/cc.bzl", "cc_binary")  # <-- wrapper

cc_binary(
    ...
    platform = "//bazel/platforms:x86_64-linux-gcc-hermetic",  # <-- only difference from upstream
    ...
)
```

## Debugging: Our toolchain

### Useful commands

Have gcc report its build configuration

```text
$ ./x86_64-checkmk-linux-gnu-gcc -v
...
Target: x86_64-checkmk-linux-gnu
Configured with: <...> --with-sysroot=/home/ctng/x-tools/x86_64-checkmk-linux-gnu/x86_64-checkmk-linux-gnu/sysroot --enable-languages=c,c++ --with-pkgversion='crosstool-NG UNKNOWN' <...> --disable-multilib <...>
...
Thread model: posix
Supported LTO compression algorithms: zlib zstd
gcc version 14.4.0 (crosstool-NG UNKNOWN)
```

List the C and C++ include dirs, respectively:

```bash
$ ./x86_64-checkmk-linux-gnu-gcc -E -xc - -v < /dev/null
...
$ ./x86_64-checkmk-linux-gnu-gcc -E -xc++ - -v < /dev/null
...
```

:::::: {.callout-info}
- Relocatable toolchain: gcc finds its include dirs and sysroot relative to
  the binary.
- Inspect the output of `-E -xc - -v` and `-E -xc++ - -v` to make sure the
  hermetic gcc does not fall back to using the host-provided headers.

::::::

## Debugging: Inspect configuration

```bash
$ bazel cquery //packages/unixcat --toolchain_resolution_debug='@bazel_tools//tools/cpp:toolchain_type' --action_env="__IGNORE=$(date +%s%N)"
INFO: Invocation ID: 0f408021-8fa2-4e9f-b814-4e323dbfca42
WARNING: Build option --action_env has changed, discarding analysis cache (this can be expensive, see https://bazel.build/advanced/performance/iteration-speed).
INFO: ToolchainResolution: Performing resolution of @@bazel_tools//tools/cpp:toolchain_type for target platform //bazel/platforms:x86_64-linux-gcc-hermetic
      ToolchainResolution:   Rejected toolchain @@toolchains_musl++toolchains_musl+musl-1_2_3-platform-aarch64-apple-darwin-target-aarch64-linux-musl//:musl-1_2_3-platform-aarch64-apple-darwin-target-aarch64-linux-musl; mismatching values: aarch64, musl
      ...
      ToolchainResolution:   Toolchain //bazel/toolchains/cc/gcc/hermetic:host_gcc is compatible with target platform, searching for execution platforms:
      ToolchainResolution:     Compatible execution platform @@platforms//host:host
      ToolchainResolution:   All execution platforms have been assigned a @@bazel_tools//tools/cpp:toolchain_type toolchain, stopping
      ToolchainResolution: Recap of selected @@bazel_tools//tools/cpp:toolchain_type toolchains for target platform //bazel/platforms:x86_64-linux-gcc-hermetic:
      ToolchainResolution:   Selected //bazel/toolchains/cc/gcc/hermetic:host_gcc to run on execution platform @@platforms//host:host
INFO: ToolchainResolution: Target platform //bazel/platforms:x86_64-linux-gcc-hermetic: Selected execution platform @@platforms//host:host, type @@bazel_tools//tools/cpp:toolchain_type -> toolchain //bazel/toolchains/cc/gcc/hermetic:host_gcc
INFO: Analyzed target //packages/unixcat:unixcat (333 packages loaded, 7680 targets configured).
INFO: Found 1 target...
//packages/unixcat:unixcat (8336c99)
INFO: Elapsed time: 0.453s, Critical Path: 0.00s
INFO: 0 processes.
INFO: Build completed successfully, 0 total actions
```

:::::: {.callout-info}
`--action_env="__IGNORE=$(date +%s%N)"` changes on every run.  This reliably
invalidates the analysis cache, so Bazel prints the resolution log again.
::::::

## Debugging: Inspect actions

```bash
$ bazel aquery 'mnemonic("CppCompile", //packages/unixcat)'  # or ... mnemonic("CppLink", ...
action 'Compiling packages/unixcat/src/unixcat.cc'
  ...
  ActionKey: 13d6e73a702f20c854f98e7c4fef85a5691b6965aa99be32befd9325c43163b1
  Inputs: [... <too long for a slide but also contains standard headers and libraries> ...]
  Outputs: [..., bazel-out/k8-fastbuild-ST-d7c9ef367ab5/bin/packages/unixcat/_objs/unixcat/unixcat.o]
  Environment: [PATH=/usr/bin:/bin]
  Command Line: (exec external/gcc_toolchain+/bin/x86_64-checkmk-linux-gnu-g++ \
    '--sysroot=external/gcc_toolchain+/x86_64-checkmk-linux-gnu/sysroot' \
    -no-canonical-prefixes \
    -fno-canonical-system-headers \
    -DNDEBUG \
    -ffunction-sections \
    -fdata-sections \
    -fPIC \
    -Wno-builtin-macro-redefined \
    '-D__DATE__="redacted"' \
    '-D__TIMESTAMP__="redacted"' \
    '-D__TIME__="redacted"' \
    '-ffile-prefix-map=__BAZEL_EXECUTION_ROOT__=.' \
    '-frandom-seed=bazel-out/k8-fastbuild-ST-d7c9ef367ab5/bin/packages/unixcat/_objs/unixcat/unixcat.o' \
    -iquote \
    . \
    -iquote \
    bazel-out/k8-fastbuild-ST-d7c9ef367ab5/bin \
    -iquote \
    external/bazel_tools \
    -iquote \
    bazel-out/k8-fastbuild-ST-d7c9ef367ab5/bin/external/bazel_tools \
    -Ibazel-out/k8-fastbuild-ST-d7c9ef367ab5/bin/packages/livestatus/_virtual_includes/livestatus_poller \
    -MD \
    -MF \
    bazel-out/k8-fastbuild-ST-d7c9ef367ab5/bin/packages/unixcat/_objs/unixcat/unixcat.d \
    -DRE2_ON_VALGRIND \
    '-std=c++20' \
    -O3 \
    -c \
    packages/unixcat/src/unixcat.cc \
    -o \
    bazel-out/k8-fastbuild-ST-d7c9ef367ab5/bin/packages/unixcat/_objs/unixcat/unixcat.o \
    -O2)
  ExecutionInfo: {manual: ''}
```

## Debugging: Inspect binary artifacts

```bash
$ bazel --quiet build //packages/unixcat
Target //packages/unixcat:unixcat up-to-date:
  bazel-bin/packages/unixcat/unixcat
```

#### readelf

```bash
$ readelf -p .comment bazel-bin/packages/unixcat/unixcat

String dump of section '.comment':
  [     0]  GCC: (crosstool-NG UNKNOWN) 14.4.0
```

#### objdump -T or nm -D

```bash
$ objdump -T bazel-bin/packages/unixcat/unixcat | grep GLIBC_
0000000000000000      DF *UND*  0000000000000000 (GLIBC_2.2.5) __errno_location
0000000000000000      DF *UND*  0000000000000000 (GLIBC_2.2.5) socket
...
0000000000000000      DF *UND*  0000000000000000 (GLIBC_2.14) memcpy
...
0000000000000000      DF *UND*  0000000000000000 (GLIBC_2.2.5) __libc_start_main
$ nm -D --undefined-only bazel-bin/packages/unixcat/unixcat | grep '@GLIBC_'
                 U connect@GLIBC_2.2.5
                 U __errno_location@GLIBC_2.2.5
                 ...
                 U memcpy@GLIBC_2.14
                 ...
                 U write@GLIBC_2.2.5
```

:::::: {.callout-info}
Highest required version: `GLIBC_2.14` ≤ 2.28, so unixcat runs on Almalinux 8.
::::::

## Handover: Pitfalls

- Law of conservation of complexity, or [Tesler's law](https://lawsofux.com/teslers-law/):

> For any system there is a certain amount of complexity which cannot be reduced.

- `foreign_cc` delegates to other build systems (autotools, make, cmake,
  meson) that are not hermetic.  Switching the toolchain on those is possible
  but requires an assessment of their dependency closure.
- Apache modules are built with apxs2, which hardcodes the host compiler by
  default.  `apxs -S CC=...` can override it, but we have not tried.
- Updating the toolchain to a newer version of gcc typically means adding multiple `-Wno-...` flags to third-party builds.
  - **Proposal:** Use *two* hermetic toolchains
    - bleeding edge for cmc, livestatus, neb, and unixcat
    - older gcc for third-party code

## Handover: Open issues

### `--sysroot`

We currently pass the `--sysroot` argument to gcc.  This is not required
(gcc finds its files relative to the location of the binary) and resulted in
linker errors with `foreign_cc` in the past.

**However** clang-tidy does require the argument:  It doesn't use gcc at
all and needs `--sysroot` to resolve the headers correctly.

The latest version of `clang_tidy.bzl` in `rules_lint` adds an `args = []`
parameter to `lint_clang_tidy_aspect()` that gets forwarded to clang-tidy.
So, we might be able to remove the `--sysroot` argument from gcc and add it
to `lint_clang_tidy_aspect()`.

### bzlmod name

Currently `bazel/thirdparty/modules/gcc_toolchain` is overly generic for a
toolchain. It might be better to version the module name to be able to add a
gcc16 next to the current gcc14, for example.

### Move to fully hermetic builds

WIP, currently low-prio
