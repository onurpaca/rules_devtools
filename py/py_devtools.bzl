"""Bundle macro for Python developer tools.

Usage:
    load("@rules_devtools//py:py_devtools.bzl", "py_devtools")
    py_devtools(name = "py_dev", srcs = ["src/**/*.py"])

Generates: ruff, black, mypy
"""

load("//py:ruff.bzl", "ruff")
load("//py:black.bzl", "black")
load("//py:mypy.bzl", "mypy")

def py_devtools(
        name,
        srcs = None,
        ruff_hermetic = None,
        ruff_system = "ruff",
        black_hermetic = None,
        black_system = "black",
        black_config = ".pyproject.toml",
        mypy_hermetic = None,
        mypy_system = "mypy",
        mypy_config = ".mypy.ini",
        **kwargs):
    """Create Python devtool targets.

    Args:
        name: Base name for generated targets.
        srcs: Glob patterns for sources. Defaults to ["**/*.py"].
        ruff_hermetic: Label to hermetic ruff binary.
        ruff_system: PATH binary name for ruff fallback.
        black_hermetic: Label to hermetic black binary.
        black_system: PATH binary name for black fallback.
        black_config: Path to black config.
        mypy_hermetic: Label to hermetic mypy binary.
        mypy_system: PATH binary name for mypy fallback.
        mypy_config: Path to mypy config.
        **kwargs: Additional common attributes.
    """
    if srcs == None:
        srcs = ["**/*.py"]

    ruff(
        name = name + "_ruff",
        srcs = srcs,
        hermetic = ruff_hermetic,
        system = ruff_system,
        **kwargs
    )
    black(
        name = name + "_black",
        srcs = srcs,
        hermetic = black_hermetic,
        system = black_system,
        config = black_config,
        **kwargs
    )
    mypy(
        name = name + "_mypy",
        srcs = srcs,
        hermetic = mypy_hermetic,
        system = mypy_system,
        config = mypy_config,
        **kwargs
    )
