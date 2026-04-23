"""Repository rule for downloading buildtools binaries (buildifier, buildozer).

Unlike LLVM tools (extracted from archives), buildtools are standalone binaries
downloaded directly from GitHub releases.
"""

load("//tools:versions.bzl", "BUILDTOOLS_VERSIONS")

def _get_buildtools_platform(rctx):
    """Determine the current platform using buildtools naming conventions.

    Buildtools uses amd64/arm64 instead of x86_64/aarch64.

    Returns:
        Platform string like "darwin-arm64", "linux-amd64", etc.
    """
    os_name = rctx.os.name.lower()
    arch = rctx.os.arch

    if "linux" in os_name:
        os_key = "linux"
    elif "mac" in os_name or "darwin" in os_name:
        os_key = "darwin"
    elif "windows" in os_name or "win" in os_name:
        os_key = "windows"
    else:
        fail("Unsupported OS: {}".format(os_name))

    if arch in ("amd64", "x86_64", "x64"):
        arch_key = "amd64"
    elif arch in ("arm64", "aarch64"):
        arch_key = "arm64"
    else:
        fail("Unsupported architecture: {}".format(arch))

    return "{}-{}".format(os_key, arch_key)

def _download_buildtools_impl(rctx):
    """Download a standalone buildtools binary for the current platform."""
    platform = _get_buildtools_platform(rctx)
    version = rctx.attr.version
    tool_name = rctx.attr.tool_name

    if version not in BUILDTOOLS_VERSIONS:
        fail("Buildtools version {} not found. Available: {}".format(
            version,
            BUILDTOOLS_VERSIONS.keys(),
        ))

    tool_versions = BUILDTOOLS_VERSIONS[version]
    if tool_name not in tool_versions:
        fail("Tool {} not found in version {}. Available: {}".format(
            tool_name,
            version,
            tool_versions.keys(),
        ))

    platform_info = tool_versions[tool_name]
    if platform not in platform_info:
        fail("Platform {} not supported for {} {}. Available: {}".format(
            platform,
            tool_name,
            version,
            platform_info.keys(),
        ))

    info = platform_info[platform]
    sha256 = info.get("sha256", "")

    # Buildtools URL pattern: standalone binary, not an archive
    exe = ".exe" if "windows" in platform else ""
    filename = tool_name + exe

    # Download into bin/ so the file path doesn't collide with the filegroup
    # target name (Bazel would otherwise resolve `srcs = ["{tool_name}"]`
    # as a self-edge to the filegroup itself).
    output_path = "bin/" + filename
    url = "https://github.com/bazelbuild/buildtools/releases/download/v{version}/{tool}-{platform}{exe}".format(
        version = version,
        tool = tool_name,
        platform = platform,
        exe = exe,
    )

    rctx.download(
        url = url,
        output = output_path,
        sha256 = sha256,
        executable = True,
    )

    # Generate BUILD.bazel exposing the binary
    rctx.file("BUILD.bazel", content = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "{tool_name}",
    srcs = ["{output_path}"],
)
""".format(
        tool_name = tool_name,
        output_path = output_path,
    ))

download_buildtools = repository_rule(
    implementation = _download_buildtools_impl,
    attrs = {
        "tool_name": attr.string(mandatory = True, doc = "Tool name (buildifier or buildozer)"),
        "version": attr.string(mandatory = True, doc = "Buildtools version to download"),
    },
)
