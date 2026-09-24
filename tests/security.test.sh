#!/usr/bin/env bash
# security.test.sh: checks that no job in .github/workflows/security.yml but
# check reads mise-action's cache. Every job computes the same cache key and
# only check writes it, so a scanner that reads it gets check's tools (see
# the workflow's header). Also runs the rule against a fixture that breaks
# it, so a rule that passes everything fails here. Needs bash and yq
# (mikefarah). No network.
#
#   bash tests/security.test.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; failures=0

# offenders <workflow>: one line per mise-action step outside check whose
# cache is not false; "none" when the workflow has no such step at all, and
# "yq failed" when it cannot be read.
offenders() {
  local steps
  steps="$(yq -r '.jobs | to_entries[] | select(.key != "check") | .key as $job
    | .value.steps[] | select((.uses // "") | test("^jdx/mise-action@"))
    | $job + " " + (.with.cache | tostring)' "$1")" || { echo "yq failed"; return; }
  [ -n "$steps" ] || { echo "none"; return; }
  printf '%s\n' "$steps" | awk '$2 != "false" { print $1 }'
}

# run <name> <workflow> <expected offenders>
run() {
  got="$(offenders "$2")"
  if [ "$got" = "$3" ]; then
    pass=$((pass + 1)); printf 'ok    %s\n' "$1"
  else
    failures=$((failures + 1)); printf 'FAIL  %s\ngot:  %s\nwant: %s\n' "$1" "$got" "$3"
  fi
}

run "security.yml: no scanner reads the mise cache" "$root/.github/workflows/security.yml" ""

cat > "$work/broken.yml" <<'EOF'
jobs:
  check:
    steps: [{uses: jdx/mise-action@x}]
  semgrep:
    steps: [{uses: jdx/mise-action@x, with: {install: false}}]
  trivy:
    steps: [{uses: jdx/mise-action@x, with: {cache: false}}]
EOF
run "fixture: a scanner with the default cache is caught" "$work/broken.yml" "semgrep"

printf 'jobs:\n  check:\n    steps: [{uses: jdx/mise-action@x}]\n' > "$work/empty.yml"
run "fixture: no scanner steps at all is caught" "$work/empty.yml" "none"

printf '\n%s passed, %s failed\n' "$pass" "$failures"
[ "$failures" = 0 ]
