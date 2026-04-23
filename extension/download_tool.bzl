"""Repository rule for downloading tools hermetically based on platform."""

load("//tools:versions.bzl", "LLVM_VERSIONS")

def _get_platform(rctx):
    """Determine the current platform."""
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

def _download_tool_impl(rctx):
    """Download and extract a tool for the current platform."""
    platform = _get_platform(rctx)
    version = rctx.attr.version

    if version not in LLVM_VERSIONS:
        fail("Version {} not found. Available: {}".format(version, LLVM_VERSIONS.keys()))

    platform_info = LLVM_VERSIONS[version]
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

    if not url:
        fail("No download URL configured for {} on {}".format(rctx.attr.tool_name, platform))

    rctx.download_and_extract(
        url = url,
        sha256 = sha256,
        stripPrefix = strip_prefix,
    )

    # Create BUILD.bazel that exports the tool binary
    binary_path = rctx.attr.binary_subpath
    rctx.file("BUILD.bazel", content = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "{tool_name}",
    srcs = ["{binary_path}"],
)
""".format(
        tool_name = rctx.attr.tool_name,
        binary_path = binary_path,
    ))

download_tool = repository_rule(
    implementation = _download_tool_impl,
    attrs = {
        "tool_name": attr.string(mandatory = True, doc = "Name of the tool"),
        "version": attr.string(mandatory = True, doc = "LLVM version to download"),
        "binary_subpath": attr.string(mandatory = True, doc = "Path to binary within the extracted archive"),
    },
)
