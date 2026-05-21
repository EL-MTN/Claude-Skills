#!/usr/bin/env bash
# build_env_metadata.sh
#
# Step 5 of the verify-change skill: assemble ONLY the runtime facts that are
# allowed to cross the independence boundary. Output goes to the test-author
# subagent.
#
# IMPORTANT: this script intentionally does NOT inspect changed source files.
# It looks at *project-level* facts only (package manifests, top-level scripts,
# obvious binary locations, log directories). The main agent must review the
# output against references/independence-boundary.md before passing it on.
#
# Usage: ./build_env_metadata.sh
# Output: markdown to stdout, suitable for embedding directly in the subagent prompt.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

echo "# Environment metadata"
echo
echo "_These are runtime facts only — what the test-author needs to RUN tests."
echo "Nothing in this block describes how the changed code works internally._"
echo

# --- Platform ---
echo "## Platform"
echo
echo "- OS: $(uname -s) $(uname -r)"
echo "- Shell: ${SHELL:-unknown}"
echo "- CWD: \`$REPO_ROOT\`"
echo

# --- Language / runtime detection ---
echo "## Detected runtimes"
echo
{
  if [[ -f package.json ]]; then
    PM=""
    if [[ -f pnpm-lock.yaml ]]; then PM="pnpm"
    elif [[ -f yarn.lock ]]; then PM="yarn"
    elif [[ -f package-lock.json ]]; then PM="npm"
    elif [[ -f bun.lockb ]] || [[ -f bun.lock ]]; then PM="bun"
    fi
    echo "- Node project (manager: ${PM:-unknown})"
    NODE_V="$(node -v 2>/dev/null || echo 'node not in PATH')"
    echo "  - node: $NODE_V"
  fi
  if [[ -f pyproject.toml ]] || [[ -f setup.py ]] || [[ -f requirements.txt ]]; then
    PY_V="$(python3 -V 2>/dev/null || echo 'python3 not in PATH')"
    echo "- Python project ($PY_V)"
    if [[ -f pyproject.toml ]] && grep -q '\[tool.poetry\]' pyproject.toml 2>/dev/null; then
      echo "  - manager: poetry"
    elif [[ -f uv.lock ]]; then
      echo "  - manager: uv"
    elif [[ -f Pipfile ]]; then
      echo "  - manager: pipenv"
    fi
  fi
  if [[ -f Cargo.toml ]]; then
    echo "- Rust project ($(rustc --version 2>/dev/null || echo 'rustc not in PATH'))"
  fi
  if [[ -f go.mod ]]; then
    echo "- Go project ($(go version 2>/dev/null || echo 'go not in PATH'))"
  fi
  if [[ -f Gemfile ]]; then
    echo "- Ruby project ($(ruby -v 2>/dev/null || echo 'ruby not in PATH'))"
  fi
} || echo "- (no manifest files detected)"
echo

# --- Test framework detection ---
echo "## Test framework + runner"
echo
TEST_RUNNERS=""
if [[ -f package.json ]]; then
  for fw in vitest jest playwright mocha ava tap; do
    if grep -q "\"$fw\"" package.json 2>/dev/null; then
      TEST_RUNNERS+="- $fw"$'\n'
    fi
  done
  # Look for a test script
  TEST_SCRIPT="$(grep -oE '"test"[[:space:]]*:[[:space:]]*"[^"]+"' package.json 2>/dev/null | head -n1 || true)"
  if [[ -n "$TEST_SCRIPT" ]]; then
    TEST_RUNNERS+="- package.json test script: $TEST_SCRIPT"$'\n'
  fi
fi
if [[ -f pyproject.toml ]] || [[ -f pytest.ini ]] || [[ -f setup.cfg ]]; then
  if grep -rq 'pytest' pyproject.toml pytest.ini setup.cfg 2>/dev/null; then
    TEST_RUNNERS+="- pytest"$'\n'
  fi
fi
if [[ -f Cargo.toml ]]; then
  TEST_RUNNERS+="- cargo test"$'\n'
fi
if [[ -f go.mod ]]; then
  TEST_RUNNERS+="- go test"$'\n'
fi
if [[ -z "$TEST_RUNNERS" ]]; then
  echo "_(no test framework detected — subagent should ask main agent to specify or document)_"
else
  echo "$TEST_RUNNERS"
fi
echo

# --- CLI binary candidates ---
echo "## CLI binary candidates"
echo
CLI_CANDIDATES=""
for d in bin cmd; do
  if [[ -d "$d" ]]; then
    for f in "$d"/*; do
      [[ -f "$f" || -L "$f" ]] && CLI_CANDIDATES+="- \`./$f\`"$'\n'
      [[ -d "$f" ]] && CLI_CANDIDATES+="- \`./$f/\` (subdir — likely a Go-style command)"$'\n'
    done
  fi
done
if [[ -f package.json ]]; then
  BIN_FIELD="$(grep -A 10 '"bin"' package.json 2>/dev/null | head -n 12 || true)"
  if [[ -n "$BIN_FIELD" ]]; then
    CLI_CANDIDATES+="- package.json bin field present (see manifest for entries)"$'\n'
  fi
fi
if [[ -z "$CLI_CANDIDATES" ]]; then
  echo "_(no obvious CLI binary detected)_"
else
  echo "$CLI_CANDIDATES"
fi
echo

# --- Dev server detection ---
echo "## Dev server"
echo
DEV_INFO=""
if [[ -f package.json ]]; then
  DEV_SCRIPT="$(grep -oE '"dev"[[:space:]]*:[[:space:]]*"[^"]+"' package.json 2>/dev/null | head -n1 || true)"
  [[ -n "$DEV_SCRIPT" ]] && DEV_INFO+="- package.json dev script: $DEV_SCRIPT"$'\n'
  START_SCRIPT="$(grep -oE '"start"[[:space:]]*:[[:space:]]*"[^"]+"' package.json 2>/dev/null | head -n1 || true)"
  [[ -n "$START_SCRIPT" ]] && DEV_INFO+="- package.json start script: $START_SCRIPT"$'\n'
fi
if [[ -f Procfile ]]; then
  DEV_INFO+="- Procfile present (heroku-style process declarations)"$'\n'
fi
if [[ -z "$DEV_INFO" ]]; then
  echo "_(no dev-server script detected)_"
else
  echo "$DEV_INFO"
  echo "_(main agent: confirm the dev URL with the user if not stated in repo docs)_"
fi
echo

# --- Log paths ---
echo "## Log paths"
echo
LOG_INFO=""
for candidate in logs log /tmp/${PWD##*/}.log .verify-change/runtime.log; do
  if [[ -d "$candidate" ]] || [[ -f "$candidate" ]]; then
    LOG_INFO+="- \`$candidate\` exists"$'\n'
  fi
done
if [[ -z "$LOG_INFO" ]]; then
  echo "_(no obvious log location detected — main agent should ask or check docs)_"
else
  echo "$LOG_INFO"
fi
echo

# --- Fixture directories ---
echo "## Fixture / sample directories"
echo
FIXTURE_DIRS=""
for d in tests/fixtures test/fixtures testdata fixtures samples examples; do
  if [[ -d "$d" ]]; then
    COUNT="$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')"
    FIXTURE_DIRS+="- \`$d/\` ($COUNT files)"$'\n'
  fi
done
if [[ -z "$FIXTURE_DIRS" ]]; then
  echo "_(no fixtures directory detected — tests may need to inline their inputs)_"
else
  echo "$FIXTURE_DIRS"
fi
echo

# --- Available MCP servers (best-effort detection) ---
echo "## Available MCP servers"
echo
echo "Main agent should fill in based on the running session. Common entries:"
echo "- Playwright MCP — for browser-driven UI tests"
echo "- Filesystem MCP — for reading log/output files"
echo

# --- Env vars (placeholder for the main agent to fill) ---
echo "## Env vars required to run"
echo
echo "_Main agent: list any env vars the test needs based on repo docs (README, .env.example)."
echo "Do NOT include secrets in this block — point at the .env.example file instead._"
echo

# --- Boundary reminder ---
echo "---"
echo
echo "**Boundary check before passing this block to the test-author subagent:**"
echo
echo "1. Did anything above name a function, class, or method from the changed code? Strip it."
echo "2. Did anything describe internal control flow? Strip it."
echo "3. Is there any quote from the diff? Strip it."
echo
echo "See \`references/independence-boundary.md\` for the full allowed/forbidden list."
