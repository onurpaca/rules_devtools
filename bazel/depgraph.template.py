"""Visualize Bazel dependency graphs using bazel query + graphviz.

Usage:
    bazel run //:deps -- //target [--depth=N] [--output=svg|html] [--no-external]
"""

import argparse
import os
import shutil
import subprocess
import sys
import html as html_module


def run_query(target, workspace_root, depth=None, no_external=False):
    """Run bazel query to get dependency graph in DOT format."""
    query_expr = f"deps({target})"
    if depth is not None:
        query_expr = f"deps({target}, {depth})"
    if no_external:
        query_expr = f"filter('^//', {query_expr})"

    cmd = ["bazel", "query", query_expr, "--output=graph"]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=workspace_root)

    if result.returncode != 0:
        print(f"\033[0;31mError:\033[0m bazel query failed.", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

    return result.stdout


def dot_to_svg(dot_content, workspace_root):
    """Convert DOT to SVG using graphviz."""
    dot_path = shutil.which("dot")
    if not dot_path:
        print("\033[0;33mWarning:\033[0m graphviz 'dot' not found. Saving raw DOT file.", file=sys.stderr)
        return None

    result = subprocess.run(
        [dot_path, "-Tsvg"],
        input=dot_content, capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"\033[0;31mError:\033[0m dot conversion failed.", file=sys.stderr)
        return None

    return result.stdout


def generate_html(svg_content, target):
    """Generate an HTML file with embedded SVG and basic zoom controls."""
    escaped_target = html_module.escape(target)
    return f"""<!DOCTYPE html>
<html>
<head>
    <title>Dependency Graph: {escaped_target}</title>
    <style>
        body {{ margin: 0; padding: 20px; font-family: sans-serif; background: #1a1a2e; color: #eee; }}
        h1 {{ font-size: 1.2em; margin-bottom: 10px; }}
        .controls {{ margin-bottom: 10px; }}
        .controls button {{ padding: 5px 15px; margin-right: 5px; cursor: pointer;
            background: #16213e; color: #eee; border: 1px solid #0f3460; border-radius: 4px; }}
        .controls button:hover {{ background: #0f3460; }}
        #graph-container {{ overflow: auto; border: 1px solid #0f3460; background: white;
            border-radius: 4px; }}
        #graph-container svg {{ transition: transform 0.2s; transform-origin: top left; }}
    </style>
</head>
<body>
    <h1>Dependency Graph: {escaped_target}</h1>
    <div class="controls">
        <button onclick="zoom(1.2)">Zoom In</button>
        <button onclick="zoom(0.8)">Zoom Out</button>
        <button onclick="resetZoom()">Reset</button>
    </div>
    <div id="graph-container">
        {svg_content}
    </div>
    <script>
        let scale = 1;
        const svg = document.querySelector('#graph-container svg');
        function zoom(factor) {{
            scale *= factor;
            svg.style.transform = 'scale(' + scale + ')';
        }}
        function resetZoom() {{
            scale = 1;
            svg.style.transform = 'scale(1)';
        }}
    </script>
</body>
</html>"""


def main():
    parser = argparse.ArgumentParser(description="Visualize Bazel dependency graphs")
    parser.add_argument("target", help="Bazel target to visualize")
    parser.add_argument("--depth", type=int, default=None, help="Maximum dependency depth")
    parser.add_argument("--output", choices=["svg", "html", "dot"], default="html", help="Output format")
    parser.add_argument("--no-external", action="store_true", help="Exclude external dependencies")
    parser.add_argument("-o", "--output-file", default=None, help="Output file path")

    args = parser.parse_args()

    workspace_root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not workspace_root:
        print("\033[0;31mError:\033[0m Must be run via 'bazel run'.", file=sys.stderr)
        sys.exit(1)

    print(f"\033[0;34mQuerying dependencies for {args.target}...\033[0m")
    dot_content = run_query(args.target, workspace_root, args.depth, args.no_external)

    if args.output == "dot":
        out_file = args.output_file or os.path.join(workspace_root, "deps.dot")
        with open(out_file, "w") as f:
            f.write(dot_content)
        print(f"\033[0;32mWrote DOT graph to {out_file}\033[0m")
        return

    svg_content = dot_to_svg(dot_content, workspace_root)

    if svg_content is None:
        # Fallback to DOT
        out_file = args.output_file or os.path.join(workspace_root, "deps.dot")
        with open(out_file, "w") as f:
            f.write(dot_content)
        print(f"\033[0;32mWrote DOT graph to {out_file}\033[0m (install graphviz for SVG/HTML)")
        return

    if args.output == "svg":
        out_file = args.output_file or os.path.join(workspace_root, "deps.svg")
        with open(out_file, "w") as f:
            f.write(svg_content)
        print(f"\033[0;32mWrote SVG graph to {out_file}\033[0m")
    else:  # html
        html_content = generate_html(svg_content, args.target)
        out_file = args.output_file or os.path.join(workspace_root, "deps.html")
        with open(out_file, "w") as f:
            f.write(html_content)
        print(f"\033[0;32mWrote HTML graph to {out_file}\033[0m")


if __name__ == "__main__":
    main()
