#!/usr/bin/env bash
# Local DocC preview for the Async Primitives umbrella catalog.
#
# Mirrors the swift-institute/.github/.github/workflows/swift-docs.yml CI pipeline:
#   1. swift build emits per-module symbol graphs (preserves @_exported doc comments)
#   2. Pool distribution graphs, excluding Test Support
#   3. (Defensive) Patch umbrella graph with doc comments + isolate to its own dir
#      per [DOC-019a] — the isolation is load-bearing for in-catalog
#      `` `Symbol` `` cross-reference resolution
#   4. xcrun docc preview against the umbrella catalog
#
# Usage: Scripts/preview-docs.sh [PORT]
#   PORT defaults to 8765. Kill existing docc preview on that port first.
#
# Dependencies:
#   - swift-institute checkout at ../../swift-institute for the patch script
#     (falls back to passing the filtered pool if the script isn't found;
#      the pool approach works when no cross-module ambiguity exists)

set -euo pipefail

PORT="${1:-8765}"
UMBRELLA_MODULE="Async_Primitives"
UMBRELLA_DISPLAY_NAME="Async Primitives"
UMBRELLA_BUNDLE_ID="swift-async-primitives.Async-Primitives"
UMBRELLA_DOCC_PATH="Sources/Async Primitives/Async Primitives.docc"
EXCLUDE_MODULES=("Async_Primitives_Test_Support")

DOCS_WORK="${DOCS_WORK:-.build/docs-work}"
RAW_DIR="${DOCS_WORK}/symbol-graphs-raw"
POOL_DIR="${DOCS_WORK}/symbol-graphs"
UMBRELLA_DIR="${DOCS_WORK}/umbrella-symbol-graph"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

PATCH_SCRIPT="$(cd "${REPO_ROOT}/../.." && pwd)/swift-institute/Scripts/patch-umbrella-symbol-graph.py"

# 0. Stop any existing docc preview on the port
if lsof -ti ":${PORT}" > /dev/null 2>&1; then
    for pid in $(lsof -ti ":${PORT}"); do
        if ps -p "${pid}" -o comm= 2>/dev/null | grep -q docc; then
            echo "stopping docc preview pid=${pid}"
            kill "${pid}" 2>/dev/null || true
        fi
    done
    sleep 1
fi

# 1. Emit symbol graphs. If the Swift build cache is warm, `swift build` will
#    skip recompilation and emit no symbol graphs — force a clean release
#    build when the raw dir comes back empty or missing the umbrella graph.
echo "==> swift build + emit symbol graphs"
rm -rf "${DOCS_WORK}"
mkdir -p "${RAW_DIR}"
build_once () {
    swift build -c debug --target "${UMBRELLA_DISPLAY_NAME}" \
        -Xswiftc -emit-symbol-graph \
        -Xswiftc -emit-symbol-graph-dir -Xswiftc "${RAW_DIR}" \
        > "${DOCS_WORK}/build.log" 2>&1
}
build_once
if [ ! -f "${RAW_DIR}/${UMBRELLA_MODULE}.symbols.json" ]; then
    echo "   cache warm — no graphs emitted; clean build to force re-emission"
    rm -rf .build/debug
    build_once
fi
echo "   raw graphs: $(ls "${RAW_DIR}" 2>/dev/null | wc -l | tr -d ' ') files"

# 2. Pool distribution graphs, minus excluded modules
echo "==> pool distribution graphs"
mkdir -p "${POOL_DIR}"
cp "${RAW_DIR}"/*.symbols.json "${POOL_DIR}/"
for excluded in "${EXCLUDE_MODULES[@]}"; do
    rm -f "${POOL_DIR}/${excluded}.symbols.json" \
          "${POOL_DIR}/${excluded}@"*.symbols.json
done
echo "   pool graphs: $(ls "${POOL_DIR}" | wc -l | tr -d ' ') files"

# 3. Narrow the umbrella graph to the Async namespace root. Multi-target
#    umbrella packages with @_exported public import chains inherit upstream
#    types (Buffer, Cardinal, Vector, …) into their symbol graph, which DocC
#    then renders in the sidebar. The filter keeps only Async.* symbols;
#    upstream types stay addressable in-source via their own modules.
NARROW_SCRIPT="${REPO_ROOT}/Scripts/narrow-umbrella-graph.py"
echo "==> narrow umbrella symbol graph to Async.*"
mkdir -p "${UMBRELLA_DIR}"
python3 "${NARROW_SCRIPT}" \
    --symbol-graph-dir "${POOL_DIR}" \
    --umbrella-module "${UMBRELLA_MODULE}" \
    --namespace-root "Async" \
    --output-dir "${UMBRELLA_DIR}"
SYMBOL_GRAPH_DIR="${UMBRELLA_DIR}"
echo "   isolated: $(ls "${UMBRELLA_DIR}" | wc -l | tr -d ' ') files"

# 4. docc preview
echo "==> xcrun docc preview on port ${PORT}"
echo "   open: http://localhost:${PORT}/documentation/async_primitives"
echo "   Semantics article: http://localhost:${PORT}/documentation/async_primitives/semantics"
echo
exec xcrun docc preview "${UMBRELLA_DOCC_PATH}" \
    --additional-symbol-graph-dir "${SYMBOL_GRAPH_DIR}" \
    --fallback-display-name "${UMBRELLA_DISPLAY_NAME}" \
    --fallback-bundle-identifier "${UMBRELLA_BUNDLE_ID}" \
    --port "${PORT}"
