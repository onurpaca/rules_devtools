"""Repository rule for downloading Python tools hermetically based on platform.

Similar approach to download_tool.bzl - archives are extracted and binary_subpath
points to the binary within the extracted structure.
"""

load("//tools:versions.bzl", "RUFF_VERSIONS")

def _get_python_platform(rctx):
    """Determine the current platform using buildtools naming conventions."""
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
        arch_key = "x86_64"
    elif arch in ("arm64", "aarch64"):
        arch_key = "aarch64"
    else:
        fail("Unsupported architecture: {}".format(arch))

    return "{}-{}".format(os_key, arch_key)

def _download_python_impl(rctx):
    """Download and extract a Python tool for the current platform."""
    platform = _get_python_platform(rctx)
    version = rctx.attr.version
    tool_name = rctx.attr.tool_name

    if version not in RUFF_VERSIONS:
        fail("Version {} not found. Available: {}".format(version, RUFF_VERSIONS.keys()))

    platform_info = RUFF_VERSIONS[version]
    if platform not in platform_info:
        fail("Platform {} not supported for version {}. Available: {}".format(
            platform,
            version,
            platform_info.keys(),
        ))

    info = platform_info[platform]
    url = info["url"]
    sha256 = info.get("sha256", "")
    strip_prefix = info.get("strip_prefix", "")
    binary_subpath = info.get("binary_subpath", tool_name)

    rctx.download_and_extract(
        url = url,
        sha256 = sha256,
        stripPrefix = strip_prefix,
    )

    rctx.file("BUILD.bazel", content = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "{tool_name}",
    srcs = ["{binary_subpath}"],
)
""".format(
        tool_name = tool_name,
        binary_subpath = binary_subpath,
    ))

download_python = repository_rule(
    implementation = _download_python_impl,
    attrs = {
        "tool_name": attr.string(mandatory = True, doc = "Tool name (ruff, black, mypy)"),
        "version": attr.string(mandatory = True, doc = "Version to download"),
    },
)
