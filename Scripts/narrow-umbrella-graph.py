#!/usr/bin/env python3
# Narrow a multi-target umbrella module's symbol graph to a single root
# namespace (e.g. 'Async'), dropping re-exported upstream symbols that
# chain-leak through `@_exported public import`.
#
# Why: DocC renders every symbol in a module's graph as a page, including
# transitively re-exported ones. An umbrella that @_exports variant targets
# (which in turn have `public import <UpstreamDep>`) inherits every
# upstream type — Buffer, Cardinal, Vector, etc. — into its graph. The
# resulting DocC sidebar buries the umbrella's own concepts under hundreds
# of unrelated upstream entries.
#
# This filter keeps only the symbols whose pathComponents are rooted at
# the given namespace (default 'Async') plus relationships internal to
# the kept set. The filtered graph is written to the output directory,
# alongside any `<Umbrella>@<OtherModule>.symbols.json` extension graphs
# (also filtered to the namespace root).
#
# Usage:
#   narrow-umbrella-graph.py \
#       --symbol-graph-dir <pool-dir> \
#       --umbrella-module Async_Primitives \
#       --namespace-root Async \
#       --output-dir <narrow-out-dir>

import argparse
import json
import sys
from pathlib import Path


def narrow_graph(graph, namespace_root):
    """Keep only symbols rooted at `namespace_root`; drop the rest."""
    symbols = graph.get("symbols", [])
    kept_usrs = set()
    kept_symbols = []
    for sym in symbols:
        path = sym.get("pathComponents", [])
        if path and path[0] == namespace_root:
            usr = sym.get("identifier", {}).get("precise")
            if usr:
                kept_usrs.add(usr)
            kept_symbols.append(sym)

    kept_relationships = [
        rel
        for rel in graph.get("relationships", [])
        if rel.get("source") in kept_usrs or rel.get("target") in kept_usrs
    ]

    narrowed = dict(graph)
    narrowed["symbols"] = kept_symbols
    narrowed["relationships"] = kept_relationships
    return narrowed, len(symbols), len(kept_symbols)


def main():
    ap = argparse.ArgumentParser(description="Narrow umbrella symbol graph to a namespace root")
    ap.add_argument("--symbol-graph-dir", required=True, type=Path)
    ap.add_argument("--umbrella-module", required=True)
    ap.add_argument("--namespace-root", required=True)
    ap.add_argument("--output-dir", required=True, type=Path)
    args = ap.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)

    umbrella_base = f"{args.umbrella_module}.symbols.json"
    umbrella_ext_prefix = f"{args.umbrella_module}@"

    found_any = False
    for path in sorted(args.symbol_graph_dir.glob("*.symbols.json")):
        name = path.name
        if name != umbrella_base and not name.startswith(umbrella_ext_prefix):
            continue
        found_any = True
        with path.open() as f:
            graph = json.load(f)
        narrowed, before, after = narrow_graph(graph, args.namespace_root)
        out_path = args.output_dir / name
        with out_path.open("w") as f:
            json.dump(narrowed, f)
        print(f"  {name}: {before} -> {after} symbols")

    if not found_any:
        print(f"error: no graphs matching '{umbrella_base}' in {args.symbol_graph_dir}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
