#!/usr/bin/env bash
# risk.test.sh: runs the "Assess risk" script from
# .github/workflows/pr-checks.yml against fixture risk.yml files, changed
# files, diffs, CODEOWNERS matches, labels and event actions, and prints ok
# or FAIL per case. Needs bash, git, jq and yq (mikefarah). No network.
#
#   bash tests/risk.test.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
wf="$root/.github/workflows/pr-checks.yml"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
yq '.jobs.checks.steps[] | select(.id == "risk") | .run' "$wf" > "$work/risk.sh"
[ -s "$work/risk.sh" ] || { echo "could not extract the risk script"; exit 1; }

pass=0; failures=0

# Per-case inputs, reset after every case:
#   RISK      the base branch's .github/risk.yml; unset means absent
#   FILES     JSON array of {filename, status, previous_filename}
#   DIFF      the pull request's diff; unset means it could not be fetched
#   OWNED     file<TAB>owners lines from the CODEOWNERS match
#   CO        1 when the base branch has a CODEOWNERS; PROTECTED its output
#   LABELS    JSON array of label names
#   ACTION    the pull_request event's action
reset() {
  RISK=''; FILES='[{"filename":"README.md","status":"modified"}]'; DIFF=''
  OWNED=''; CO=0; PROTECTED=''; LABELS='["class:feature"]'; ACTION=opened
}
reset

# run <name> <expected exit> <expected outputs, space separated k=v> <expected text or ""> [unwanted text]
run() {
  local name="$1" want="$2" outs="$3" grepfor="$4" unwanted="${5:-}" o
  rm -f "$work/risk.yml" "$work/pr.diff" "$work/CODEOWNERS" "$work/output" "$work/comment.md"
  [ -n "${RISK+set}" ] && printf '%s\n' "$RISK" > "$work/risk.yml"
  [ -n "${DIFF+set}" ] && printf '%s' "$DIFF" > "$work/pr.diff"
  [ "$CO" = 1 ] && echo '* @x' > "$work/CODEOWNERS"
  printf '%s' "$FILES" > "$work/files.json"
  jq -r '.[] | .filename, (.previous_filename // empty)' "$work/files.json" > "$work/files.txt"
  printf '%s' "$OWNED" > "$work/owned.tsv"
  printf '%s' "$LABELS" > "$work/labels.json"
  out="$(RISK_FILE="$work/risk.yml" FILES_FILE="$work/files.txt" FILES_JSON="$work/files.json" \
    DIFF_FILE="$work/pr.diff" CODEOWNERS_FILE="$work/CODEOWNERS" OWNED_FILE="$work/owned.tsv" \
    PROTECTED="$PROTECTED" LABELS_FILE="$work/labels.json" EVENT_ACTION="$ACTION" \
    COMMENT_FILE="$work/comment.md" GITHUB_OUTPUT="$work/output" bash "$work/risk.sh" 2>&1)"
  got=$?
  out="$out"$'\n'"$(cat "$work/comment.md" 2>/dev/null)"
  local ok=1
  for o in $outs; do
    if [ "$o" = none ]; then
      [ ! -s "$work/output" ] || { ok=0; out="$out"$'\n'"want no outputs, got: $(cat "$work/output")"; }
    elif ! grep -Fxq -- "$o" "$work/output" 2>/dev/null; then
      ok=0; out="$out"$'\n'"want output $o, got: $(tr '\n' ' ' < "$work/output" 2>/dev/null)"
    fi
  done
  if [ "$got" = "$want" ] && [ "$ok" = 1 ] \
      && { [ -z "$grepfor" ] || printf '%s' "$out" | grep -Fq -- "$grepfor"; } \
      && { [ -z "$unwanted" ] || ! printf '%s' "$out" | grep -Fq -- "$unwanted"; }; then
    pass=$((pass + 1)); printf 'ok    %s\n' "$name"
  else
    failures=$((failures + 1)); printf 'FAIL  %s (exit %s, want %s)\n%s\n' "$name" "$got" "$want" "$out"
  fi
  reset
}

# diff <file> <removed lines> <added lines>: one hunk changing a file.
diff() {
  printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1,3 +1,3 @@\n context\n' "$1" "$1" "$1" "$1"
  [ -z "$2" ] || printf '%s\n' "$2" | sed 's/^/-/'
  [ -z "$3" ] || printf '%s\n' "$3" | sed 's/^/+/'
}
mod() { printf '{"filename":"%s","status":"modified"}' "$1"; }

# Opt-in.
unset RISK
run "no risk.yml: nothing decided, nothing labelled" 0 "none" "No .github/risk.yml on the base branch"
RISK=''
run "an empty risk.yml opts in"                      0 "level=low add=risk:low remove= unreview=false" "Risk: **low**"

# Levels, first match wins: fixed, weakened test, rule, test file,
# CODEOWNERS, default.
run "unmatched file: default low, no gate"           0 "level=low add=risk:low" "no review gate below high"
RISK='default: medium'
run "default sets the unmatched file's level"        0 "level=medium add=risk:medium" ""
RISK=$'rules:\n  - paths: ["src/**"]\n    level: medium\n    question: Does the parser still reject a blank total?'
FILES="[$(mod src/Parser.cs)]"
run "a rule sets medium, with its question"          0 "level=medium add=risk:medium" '- **medium** `src/Parser.cs`: Does the parser still reject a blank total?'
CO=1; PROTECTED=true; OWNED=$'infra/main.tf\t@ops'; FILES="[$(mod infra/main.tf)]"
run "a CODEOWNERS path is high, gate refuses"        1 "level=high add=risk:high" "an owner adds the owner-reviewed label"
CO=1; PROTECTED=true; OWNED=$'infra/main.tf\t@ops'; FILES="[$(mod infra/main.tf)]"
run "the comment says why a CODEOWNERS file is high" 1 "level=high" '- **high** `infra/main.tf`: Owned by @ops in CODEOWNERS.'
CO=1; PROTECTED=true; OWNED=$'infra/main.tf\t@ops'; FILES="[$(mod infra/main.tf)]"
RISK=$'rules:\n  - paths: ["/infra/**"]\n    level: low\n    question: Plan output attached?'
run "a rule lowers a CODEOWNERS path"                0 "level=low add=risk:low" "Plan output attached?"
CO=1; PROTECTED=true; OWNED=$'tests/ParserTests.cs\t@ops'; FILES="[$(mod tests/ParserTests.cs)]"
run "an owned test file, not weakened, is low"       0 "level=low" ""
RISK=$'rules:\n  - paths: ["src/**"]\n    level: high\n  - paths: ["src/docs/**"]\n    level: low'
FILES="[$(mod src/docs/a.md)]"
run "the last matching rule decides"                 0 "level=low" ""
RISK=$'rules:\n  - paths: ["src/docs/**"]\n    level: low\n  - paths: ["src/**"]\n    level: high'
FILES="[$(mod src/docs/a.md)]"
run "the last matching rule decides, reversed"       1 "level=high" "Matches rule 2 (src/**)."
RISK=$'rules:\n  - paths: ["a/**", "c/**"]\n    level: medium\n  - paths: ["b/**"]\n    level: high'
FILES="[$(mod a/x),$(mod b/y),$(mod c/z),$(mod d/w)]"
run "the highest file decides the pull request"      1 "level=high" "Why: 3 file(s) with a reason below, 0 heuristic hit(s)"
RISK=$'rules:\n  - paths: ["/.github/workflows/**", "/decisions/**"]\n    level: low'
FILES="[$(mod .github/workflows/ci.yml)]"
run "a fixed high path beats a rule"                 1 "level=high" 'Always high'
for f in .github/CODEOWNERS decisions/0016-x.md product/invariants.md; do
  FILES="[$(mod "$f")]"
  run "$f is always high"                            1 "level=high" "Always high"
done
FILES="[$(mod src/decisions/x.md),$(mod docs/product/invariants.md)]"
run "fixed paths are anchored at the root"           0 "level=low" ""
CO=1; PROTECTED=''
run "an unfinished CODEOWNERS match fails closed"    1 "" "The CODEOWNERS match did not finish"

# Config errors.
RISK=$'rules:\n  - paths: ["src/**"]\n    level: severe'
run "an unknown level is refused"                    1 "" "is not valid"
RISK=$'rules:\n  - level: high'
run "a rule with no paths is refused"                1 "" "is not valid"
RISK=$'rules:\n  - paths: "src/**"\n    level: high'
run "a rule's paths must be a list"                  1 "" "is not valid"
RISK='default: none'
run "an unknown default is refused"                  1 "" "is not valid"
RISK='tests: tests/'
run "tests must be a list"                           1 "" "is not valid"
RISK=': : not yaml ['
run "unreadable YAML is refused"                     1 "" "Could not read .github/risk.yml"

# The base branch's config, not the head's: a pull request that rewrites
# risk.yml to lower its own files is still judged by the base's copy, and
# risk.yml is a fixed high path.
RISK=$'rules:\n  - paths: ["infra/**"]\n    level: high'
FILES="[$(mod infra/main.tf),$(mod .github/risk.yml)]"
DIFF="$(diff .github/risk.yml '    level: high' '    level: low')"
run "a head that lowers risk.yml is judged by base" 1 "level=high" '- **high** `infra/main.tf`: Matches rule 1'

# Weakened tests.
FILES='[{"filename":"tests/ParserTests.cs","status":"removed"}]'
run "a deleted test file is high"                    1 "level=high" '`tests/ParserTests.cs`: Weakened test: deleted.'
RISK=$'rules:\n  - paths: ["tests/**"]\n    level: low'
FILES='[{"filename":"tests/ParserTests.cs","status":"removed"}]'
run "a weakened test beats a rule"                   1 "level=high" "Test files deleted or moved out of the test paths: 1."
FILES='[{"filename":"attic/ParserTests.bak","previous_filename":"src/Parser.Tests/ParserTests.cs","status":"renamed"}]'
run "a test renamed out of the test paths is high"   1 "level=high" "moved out of the test paths to"
FILES='[{"filename":"tests/unit/ParserTests.cs","previous_filename":"tests/ParserTests.cs","status":"renamed"}]'
run "a test renamed within the test paths is not"    0 "level=low" ""
FILES='[{"filename":"src/Parser.cs","status":"removed"}]'
run "a deleted non-test file is not a test hit"      0 "level=low" ""
FILES="[$(mod tests/ParserTests.cs)]"
DIFF="$(diff tests/ParserTests.cs $'        Assert.Equal(2, x);\n        Assert.True(y);\n        x.Should().Be(3);' '        Assert.Equal(2, x);')"
run "assertions removed net are high, with counts"  1 "level=high" "Weakened test: 3 assertion lines removed, 1 added."
FILES="[$(mod tests/a.test.ts)]"
DIFF="$(diff tests/a.test.ts '  expect(x).toBe(1);' '  expect(x).toBe(2);')"
run "an assertion changed in place is not a hit"     0 "level=low" "" "assertion"
FILES="[$(mod tests/a.test.ts),$(mod tests/b.test.ts)]"
DIFF="$(diff tests/a.test.ts '  expect(x).toBe(1);' ''; diff tests/b.test.ts '' '  expect(x).toBe(1);')"
run "an assertion moved out of a file flags it"      1 "level=high" '`tests/a.test.ts`: Weakened test: 1 assertion lines removed, 0 added.' '`tests/b.test.ts`: Weakened'
FILES="[$(mod src/Guard.cs)]"
DIFF="$(diff src/Guard.cs '    Debug.Assert(x);' '')"
run "assertions outside test files are not counted"  0 "level=low" ""
FILES="[$(mod tests/test_parse.py)]"
DIFF="$(diff tests/test_parse.py '    assert total == 2' '    total == 2')"
run "a python assert removed is high"                1 "level=high" "1 assertion lines removed, 0 added"
FILES="[$(mod tests/ParserTests.cs)]"
DIFF="$(diff tests/ParserTests.cs '    [Fact]' '    [Fact(Skip = "flaky")]')"
run "a skip attribute added is high"                 1 "level=high" "1 skip or ignore markers added, 0 removed."
FILES="[$(mod tests/a.test.ts)]"
DIFF="$(diff tests/a.test.ts '  it.skip("parses", () => {' '  it("parses", () => {')"
run "a skip removed is not a hit"                    0 "level=low" "" "skip or ignore"
FILES="[$(mod coverage-baseline.json)]"
DIFF="$(diff coverage-baseline.json '  "AccountsPayable": 412,' '  "AccountsPayable": 398,')"
run "a lowered coverage number is high"              1 "level=high" '`coverage-baseline.json`: Weakened test: a number lowered, 412 to 398.'
FILES="[$(mod coverage-baseline.json)]"
DIFF="$(diff coverage-baseline.json '  "AccountsPayable": 412,' '  "AccountsPayable": 430,')"
run "a raised coverage number is not"                0 "level=low" "" "lowered"
FILES="[$(mod src/limits.json)]"
DIFF="$(diff src/limits.json '  "max": 412,' '  "max": 398,')"
run "a lowered number outside coverage files is not" 0 "level=low" ""
FILES='[{"filename":".config/ratchet.json","status":"removed"}]'
run "a deleted coverage file is high"                1 "level=high" "Weakened test: coverage file deleted."
unset DIFF
FILES="[$(mod tests/a.test.ts)]"
run "no diff: high by default"                       1 "level=high" "The diff could not be fetched"
RISK=$'tests: ["/spec/"]\ncoverage: ["/gates.json"]'
FILES='[{"filename":"tests/a.test.ts","status":"removed"},{"filename":"spec/b.rb","status":"removed"},{"filename":"gates.json","status":"modified"}]'
DIFF="$(diff gates.json '  "line": 80,' '  "line": 70,')"
run "tests and coverage replace the defaults"        1 "level=high" '`spec/b.rb`: Weakened test: deleted.' '`tests/a.test.ts`: Weakened'
RISK=$'tests: ["/spec/"]\ncoverage: ["/gates.json"]'
FILES="[$(mod gates.json)]"
DIFF="$(diff gates.json '  "line": 80,' '  "line": 70,')"
run "a configured coverage glob is used"             1 "level=high" "a number lowered, 80 to 70"
FILES='[{"filename":"src/a\nb.cs","status":"modified"}]'
run "a file name with a line break is high"          1 "level=high" "control characters: 1"
FILES='[{"filename":"tests/a`b.test.ts","status":"removed"}]'
run "a file name cannot break out of its code span"  1 "level=high" "\`tests/a'b.test.ts\`"

# Labels and the gate.
CO=1; PROTECTED=true; OWNED=$'infra/main.tf\t@ops'; FILES="[$(mod infra/main.tf)]"
LABELS='["class:feature","owner-reviewed","risk:high"]'; ACTION=labeled
run "high with owner-reviewed passes"                0 "level=high add= remove= unreview=false" "owner-reviewed is present"
CO=1; PROTECTED=true; OWNED=$'infra/main.tf\t@ops'; FILES="[$(mod infra/main.tf)]"
LABELS='["class:feature","owner-reviewed","risk:high"]'; ACTION=synchronize
run "a push removes owner-reviewed and refuses"      1 "level=high unreview=true" "A push removed owner-reviewed"
LABELS='["owner-reviewed","risk:low"]'; ACTION=synchronize
run "a push removes owner-reviewed at low too"       0 "level=low add= unreview=true" ""
LABELS='["owner-reviewed"]'; ACTION=edited
run "owner-reviewed stays on other events"           0 "unreview=false" ""
LABELS='["risk:low","risk:medium","class:x"]'
CO=1; PROTECTED=true; OWNED=$'infra/main.tf\t@ops'; FILES="[$(mod infra/main.tf)]"
run "stale risk labels are removed"                  1 "add=risk:high remove=risk:medium,risk:low" ""
LABELS='["risk:medium"]'
run "the current label is kept, a stale one goes"    0 "level=low add=risk:low remove=risk:medium" ""

# The comment.
run "the comment starts with its marker"             0 "" "<!-- pap:review-focus -->"
if [ "$(head -n 1 "$work/comment.md")" = '<!-- pap:review-focus -->' ] && [ "$(grep -c 'pap:review-focus' "$work/comment.md")" = 1 ]; then
  pass=$((pass + 1)); echo "ok    the marker is the first line, once"
else
  failures=$((failures + 1)); echo "FAIL  the marker is the first line, once"; cat "$work/comment.md"
fi

# The workflow: the config comes from the base commit, owner-reviewed is
# removed before anything else on a push, and its failure fails the job.
fetch="$(yq '.jobs.checks.steps[] | select(.id == "fetch") | .run' "$wf")"
check() { # check <name> <condition result>
  if [ "$2" = 0 ]; then pass=$((pass + 1)); printf 'ok    %s\n' "$1"; else failures=$((failures + 1)); printf 'FAIL  %s\n' "$1"; fi
}
grep -Fq 'contents/.github/risk.yml?ref=$BASE_SHA' <<< "$fetch"; check "risk.yml is read at the base commit" $?
[ "$(yq '.jobs.checks.steps[] | select(.id == "fetch") | .env.BASE_SHA' "$wf")" = '${{ github.event.pull_request.base.sha }}' ]
check "BASE_SHA is the pull request's base" $?
apply="$(yq '.jobs.checks.steps[] | select(.name == "Apply the risk label and the Review focus comment") | .run' "$wf")"
grep -Eq 'labels/owner-reviewed" > /dev/null \\?$' <<< "$apply" && grep -Fq 'exit 1' <<< "$apply"
check "a failed owner-reviewed removal fails the job" $?
[ "$(yq '.permissions | to_entries | map(.key + ":" + .value) | join(",")' "$wf")" = 'contents:read,pull-requests:write' ]
check "permissions stay contents: read, pull-requests: write" $?
! grep -Eq 'actions/checkout|pull_request_target' <<< "$(yq '.jobs.checks.steps[] | (.uses // "") + (.run // "")' "$wf")"
check "no step checks out or runs head code" $?

printf '\n%s passed, %s failed\n' "$pass" "$failures"
[ "$failures" = 0 ]
