#!/usr/bin/env bash
# security.test.sh: checks two rules on .github/workflows/security.yml (see
# the workflow's header for both). No job but check reads mise-action's
# cache: every job computes the same cache key and only check writes it, so
# a scanner that reads it gets check's tools. Every tool `mise exec` runs is
# installed by `mise install` earlier in the same step: exec's own install
# skips the mise-versions mirror and spends api.github.com's anonymous rate
# limit. Each rule also runs against a fixture that breaks it, so a rule
# that passes everything fails here. Needs bash and yq (mikefarah). No
# network.
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

# uninstalled <workflow>: one line per `mise exec "<spec>"` with no
# `mise install "<spec>"` before it in the same step, as "<job> <spec>";
# "none" when the workflow runs no `mise exec` at all, and "yq failed" when
# it cannot be read.
uninstalled() {
  local runs job b64 script spec found=0
  runs="$(yq -r '.jobs | to_entries[] | .key as $job | .value.steps[]
    | select(.run) | $job + " " + (.run | @base64)' "$1")" || { echo "yq failed"; return; }
  while read -r job b64; do
    [ -n "$job" ] || continue
    script="$(printf '%s' "$b64" | base64 -d)"
    while read -r spec; do
      [ -n "$spec" ] || continue
      found=1
      printf '%s\n' "$script" | awk -v s="$spec" '
        index($0, "mise install \"" s "\"") { installed = 1 }
        index($0, "mise exec \"" s "\"") { exit !installed }' || echo "$job $spec"
    done <<< "$(printf '%s\n' "$script" | grep -o 'mise exec "[^"]*"' | sed 's/^mise exec "//; s/"$//')"
  done <<< "$runs"
  [ "$found" = 1 ] || echo "none"
}

# run <name> <workflow> <expected offenders> [rule, default offenders]
run() {
  got="$("${4:-offenders}" "$2")"
  if [ "$got" = "$3" ]; then
    pass=$((pass + 1)); printf 'ok    %s\n' "$1"
  else
    failures=$((failures + 1)); printf 'FAIL  %s\ngot:  %s\nwant: %s\n' "$1" "$got" "$3"
  fi
}

run "security.yml: no scanner reads the mise cache" "$root/.github/workflows/security.yml" ""
run "security.yml: every tool mise exec runs is installed first" "$root/.github/workflows/security.yml" "" uninstalled

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

# gitleaks is right; trivy installs after the exec; semgrep installs in an
# earlier step, which this rule does not accept.
cat > "$work/exec.yml" <<'EOF'
jobs:
  gitleaks:
    steps:
      - run: |
          mise install "gitleaks@$V"
          mise exec "gitleaks@$V" -- gitleaks git .
  trivy:
    steps:
      - run: |
          mise exec "trivy@$V" -- trivy fs .
          mise install "trivy@$V"
  semgrep:
    steps:
      - run: mise install "pipx:semgrep@$V"
      - run: mise exec "pipx:semgrep@$V" -- semgrep scan
EOF
# shellcheck disable=SC2016 # $V is literal text in the fixture.
run "fixture: an exec with no install before it is caught" "$work/exec.yml" \
  "$(printf '%s\n' 'trivy trivy@$V' 'semgrep pipx:semgrep@$V')" uninstalled

printf 'jobs:\n  trivy:\n    steps: [{run: trivy fs .}]\n' > "$work/noexec.yml"
run "fixture: no mise exec at all is caught" "$work/noexec.yml" "none" uninstalled

printf '\n%s passed, %s failed\n' "$pass" "$failures"
[ "$failures" = 0 ]
