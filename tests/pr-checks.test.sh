#!/usr/bin/env bash
# pr-checks.test.sh: runs the inline check script from
# .github/workflows/pr-checks.yml against fixture titles, bodies and commit
# messages. Needs bash, jq, perl and yq (mikefarah). No network.
#
#   bash tests/pr-checks.test.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
yq '.jobs.checks.steps[] | select(.id == "check") | .run' \
  "$root/.github/workflows/pr-checks.yml" > "$work/check.sh"
[ -s "$work/check.sh" ] || { echo "could not extract the check script"; exit 1; }

pass=0; failures=0

# run <name> <expected exit> <expected text or ""> <title> <body> [author type] [commit message...]
run() {
  local name="$1" want="$2" grepfor="$3" title="$4" body="$5" author="${6:-User}"
  shift 6 2>/dev/null || shift $#
  if [ $# -gt 0 ]; then printf '%s\0' "$@" | jq -R -s 'split("\u0000") | map(select(length > 0))' > "$work/commits.json"
  else echo '[]' > "$work/commits.json"; fi
  out="$(PR_TITLE="$title" PR_BODY="$body" PR_AUTHOR_TYPE="$author" COMMITS_FILE="$work/commits.json" bash "$work/check.sh" 2>&1)"
  got=$?
  if [ "$got" = "$want" ] && { [ -z "$grepfor" ] || printf '%s' "$out" | grep -Fq "$grepfor"; }; then
    pass=$((pass + 1)); printf 'ok    %s\n' "$name"
  else
    failures=$((failures + 1)); printf 'FAIL  %s (exit %s, want %s)\n%s\n' "$name" "$got" "$want" "$out"
  fi
}

checks() { # checks <box1> <box2> <box3> [trailing text]
  printf '## Summary\nSomething.\n\n## Checks\nTick a box only if it is true. An unticked box needs a one-line reason below it, otherwise the PR is not ready.\n%s\n%s\n%s\n%s' "$1" "$2" "$3" "${4:-}"
}
V='- [x] Verification run and output shown above'
P='- [x] No protected path touched, or the approval is recorded here'
G='- [x] Generated content carries provenance (model, skill, prompt)'
Vu='- [ ] Verification run and output shown above'
Pu='- [ ] No protected path touched, or the approval is recorded here'
Gu='- [ ] Generated content carries provenance (model, skill, prompt)'
CLAUDE=$'build(x): y\n\nCo-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>'
HUMAN=$'docs: fix a typo'

run "filled template, generated, trailer"          0 "pass" "build(template): add the .NET layer" "$(checks "$V" "$P" "$G")" User "$CLAUDE"
run "provenance recorded by a body line only"      0 "" "docs(readme): tidy" "$(checks "$V" "$P" "$G" $'\nProvenance: Claude, prompt "tidy"')" User "$HUMAN"
run "human PR, provenance unticked with reason"    0 "" "docs: fix a typo" "$(checks "$V" "$P" "$Gu" 'No generated content.')" User "$HUMAN"
run "squash-style lower-case trailer counts"       0 "" "fix(guard): x" "$(checks "$V" "$P" "$G")" User $'fix\n\nCo-authored-by: Claude Fable 5.1 <noreply@anthropic.com>'
run "breaking change marker and dashed scope"      0 "" "feat(spec-review)!: drop x" "$(checks "$V" "$P" "$G")" User "$CLAUDE"
run "process title with a record"                  0 "" "process: record 0004, pr checks" "$(printf 'Record: 0004\n\n%s' "$(checks "$V" "$P" "$G")")" User "$CLAUDE"
run "unticked box inside an HTML comment ignored"  0 "" "chore: x" "$(checks "$V" "$P" "$G" $'\n<!--\n- [ ] draft note\n-->')" User "$CLAUDE"
run "task list outside Checks is not checked"      0 "" "chore: x" "$(printf '## Plan\n- [ ] later\n\n%s' "$(checks "$V" "$P" "$G")")" User "$CLAUDE"
run "bot author passes unchecked"                  0 "bot" "Bump lodash from 1 to 2" "no template" Bot

pr21=$'Change: none\r\nRecord: 0003\r\n\r\n## Summary\r\nThe record.\r\n\r\n## Checks\r\nTick a box only if it is true. An unticked box needs a one-line reason below it, otherwise the PR is not ready.\r\n- [ ] Verification run and output shown above\r\n- [ ] No protected path touched, or the approval is recorded here\r\n- [ ] Generated content carries provenance (model, skill, prompt)'
run "PR #21: CRLF, three unexplained boxes"        1 "Unticked with no reason on the next line: 'Generated content" "process: record 0003, template layers compose additively" "$pr21" User $'process: record 0003, template layers compose additively\n\nRecord: 0003'
run "reason after a blank line does not count"     1 "Unticked with no reason" "docs: x" "$(checks "$V" "$P" "$Gu" $'\nNo generated content.')" User "$HUMAN"
run "two unticked in a row: first is unexplained"  1 "Verification run" "docs: x" "$(checks "$Vu" "$Pu" "$G" )" User "$CLAUDE"
run "title without a type"                         1 "not a conventional commit" "Add the .NET layer" "$(checks "$V" "$P" "$G")" User "$CLAUDE"
run "title with an unknown type"                   1 "not a conventional commit" "feature: x" "$(checks "$V" "$P" "$G")" User "$CLAUDE"
run "title with a capitalised type"                1 "not a conventional commit" "Docs: x" "$(checks "$V" "$P" "$G")" User "$CLAUDE"
run "process title without a record"               1 "Record: NNNN" "process: change the gate" "$(checks "$V" "$P" "$G")" User "$CLAUDE"
run "process title with Record: none"              1 "Record: NNNN" "process: change the gate" "$(printf 'Record: none\n\n%s' "$(checks "$V" "$P" "$G")")" User "$CLAUDE"
run "no Checks section"                            1 "No '## Checks' section" "docs: x" $'## Summary\nJust text.' User "$HUMAN"
run "provenance box missing"                       1 "no 'Generated content carries provenance' box" "docs: x" "$(printf '## Checks\n%s\n%s\n' "$V" "$P")" User "$CLAUDE"
run "provenance ticked, nothing recorded"          1 "ticked but not recorded" "docs: x" "$(checks "$V" "$P" "$G")" User "$HUMAN"
run "Claude trailer, provenance unticked"          1 "provenance box is unticked" "build: x" "$(checks "$V" "$P" "$Gu" 'None.')" User "$CLAUDE"
run "Generated-with line, provenance unticked"     1 "provenance box is unticked" "build: x" "$(checks "$V" "$P" "$Gu" $'None.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')" User "$HUMAN"

printf '\n%s passed, %s failed\n' "$pass" "$failures"
[ "$failures" = 0 ]
