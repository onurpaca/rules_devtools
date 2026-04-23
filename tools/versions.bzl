# LLVM/Clang tools - used by format, lint.
#
# Two packaging formats coexist on GitHub:
#   - LLVM <= 18: clang+llvm-<ver>-<triple>-<base>.tar.xz, built on Ubuntu 18.04
#     (binaries depend on libtinfo.so.5, which is unavailable on modern distros)
#   - LLVM >= 19: LLVM-<ver>-Linux-X64.tar.xz (CMake/CPack packaging),
#     built on a newer base — only depends on glibc, libstdc++, libm, libz, libgcc_s
#
# No official darwin-x86_64 prebuilt is published for any recent version.
LLVM_VERSIONS = {
    "22.1.4": {
        "linux-x86_64": {
            "url": "https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.4/LLVM-22.1.4-Linux-X64.tar.xz",
            "sha256": "cdf232e3bc5d9909ddcf8cb7016802c6745a01e69a596747c684caa894a11567",
            "strip_prefix": "LLVM-22.1.4-Linux-X64",
        },
        "linux-aarch64": {
            "url": "https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.4/LLVM-22.1.4-Linux-ARM64.tar.xz",
            "sha256": "ac8bed48a6481ccc0e14af18f64d44fc1ca8c0ccf630c1d4dc5e97027e87e6fa",
            "strip_prefix": "LLVM-22.1.4-Linux-ARM64",
        },
        "darwin-aarch64": {
            "url": "https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.4/LLVM-22.1.4-macOS-ARM64.tar.xz",
            "sha256": "45e0dfc0453624caed5e7b20e224ce8343af9c511c7f59803753a586620d6ad1",
            "strip_prefix": "LLVM-22.1.4-macOS-ARM64",
        },
        "windows-x86_64": {
            "url": "https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.4/clang+llvm-22.1.4-x86_64-pc-windows-msvc.tar.xz",
            "sha256": "ed775bdaea7087c6c1aeac9498352cfcd8610d92dc4fe9eda9aecb15ce712a2c",
            "strip_prefix": "clang+llvm-22.1.4-x86_64-pc-windows-msvc",
        },
    },
    "18.1.8": {
        "linux-x86_64": {
            "url": "https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz",
            "sha256": "54ec30358afcc9fb8aa74307db3046f5187f9fb89fb37064cdde906e062ebf36",
            "strip_prefix": "clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04",
        },
        "linux-aarch64": {
            "url": "https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/clang+llvm-18.1.8-aarch64-linux-gnu.tar.xz",
            "sha256": "dcaa1bebbfbb86953fdfbdc7f938800229f75ad26c5c9375ef242edad737d999",
            "strip_prefix": "clang+llvm-18.1.8-aarch64-linux-gnu",
        },
        "darwin-aarch64": {
            "url": "https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/clang+llvm-18.1.8-arm64-apple-macos11.tar.xz",
            "sha256": "4573b7f25f46d2a9c8882993f091c52f416c83271db6f5b213c93f0bd0346a10",
            "strip_prefix": "clang+llvm-18.1.8-arm64-apple-macos11",
        },
        "windows-x86_64": {
            "url": "https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/clang+llvm-18.1.8-x86_64-pc-windows-msvc.tar.xz",
            "sha256": "22c5907db053026cc2a8ff96d21c0f642a90d24d66c23c6d28ee7b1d572b82e8",
            "strip_prefix": "clang+llvm-18.1.8-x86_64-pc-windows-msvc",
        },
    },
}

DEFAULT_LLVM_VERSION = "22.1.4"

# Tool binary paths within the LLVM distribution.
# Only tools that ship inside the LLVM distribution belong here.
LLVM_TOOLS = {
    "clang-format": "bin/clang-format",
    "clang-tidy": "bin/clang-tidy",
}

# Buildtools (buildifier, buildozer) — standalone binary downloads
DEFAULT_BUILDTOOLS_VERSION = "8.5.1"

BUILDTOOLS_VERSIONS = {
    "8.5.1": {
        "buildifier": {
            "linux-amd64": {"sha256": "887377fc64d23a850f4d18a077b5db05b19913f4b99b270d193f3c7334b5a9a7"},
            "linux-arm64": {"sha256": "947bf6700d708026b2057b09bea09abbc3cafc15d9ecea35bb3885c4b09ccd04"},
            "darwin-amd64": {"sha256": "31de189e1a3fe53aa9e8c8f74a0309c325274ad19793393919e1ca65163ca1a4"},
            "darwin-arm64": {"sha256": "62836a9667fa0db309b0d91e840f0a3f2813a9c8ea3e44b9cd58187c90bc88ba"},
            "windows-amd64": {"sha256": "f4ecb9c73de2bc38b845d4ee27668f6248c4813a6647db4b4931a7556052e4e1"},
        },
        "buildozer": {
            "linux-amd64": {"sha256": "2b745ca2ad41f1e01673fb59ac50af6b45ca26105c1d20fad64c3d05a95522f5"},
            "linux-arm64": {"sha256": "87ee1d2d81d08ccae8f9147fc58503967c85878279e892f2990912412feef1a1"},
            "darwin-amd64": {"sha256": "b85b9ad59c1543999a5d8bc8bee6e42b9f025be3ff520bc2d090213698850b43"},
            "darwin-arm64": {"sha256": "d0cf2f6e11031d62bfd4584e46eb6bb708a883ff948be76538b34b83de833262"},
            "windows-amd64": {"sha256": "e177155c2c8ef41569791de34f13077cefe3e5623f9f02e099347232bc028901"},
        },
    },
}

BUILDTOOLS_TOOLS = ["buildifier", "buildozer"]
