# blairforce1/.github

Default community health files for every repository owned by blairforce1.
Authored in [blairforce1/pap](https://github.com/blairforce1/pap) under
`org-github/`, which mirrors this repository's layout. Edit there and push
here.

## Inheritance

A repository owned by this account that has no file of a given type uses
the one here. The file does not appear in that repository's file browser,
history, clones, or downloads. A repository with its own file of the type
keeps its own; a repository with its own issue templates shows only its
own. Lookup order, both in a repository and in here, is `.github/`, then
the root, then `docs/`.

This repository must be public. The defaults then apply to every repository
owned by the account regardless of that repository's visibility, so private
repositories on a Pro personal account inherit them. GitHub's documentation
makes no distinction by plan, or between organisations and personal
accounts.

### Inherited from here

| File | Where it must live in this repository | Provided |
|---|---|---|
| `PULL_REQUEST_TEMPLATE.md` | root, `.github/`, or `docs/` | yes, root |
| Issue forms and `config.yml` | `.github/ISSUE_TEMPLATE/` only | yes |
| `SECURITY.md` | root, `.github/`, or `docs/` | yes, root |
| `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SUPPORT.md` | root, `.github/`, or `docs/` | no |
| `FUNDING.yml` | `.github/` | no |
| Discussion category forms | `.github/DISCUSSION_TEMPLATE/` | no |

### Not inherited

- `CODEOWNERS`: read only from the repository being changed, from its
  `.github/`, root, or `docs/`. Each repository needs its own.
- `LICENSE`: GitHub refuses a default so that clones and downloads carry
  the licence.
- `README.md`: this file describes this repository only. The account
  profile README lives in `blairforce1/blairforce1`.
- Workflows, `dependabot.yml`, labels, rulesets, branch protection: all per
  repository. A repository can call a reusable workflow from here; see
  "Reusable workflows". Starter workflows in `workflow-templates/` are an organisation
  feature and do not apply to a personal account.

## Reusable workflows

Workflows are not inherited: a repository runs one only by calling it.
`.github/workflows/pr-checks.yml` checks a pull request's title and body
against the PAP rules. It refuses a title that is not a conventional commit,
a `process:` title with no `Record: NNNN` line, a box in `## Checks` left
unticked with no reason on the line below it, a ticked provenance box with
no `Co-authored-by` trailer on any commit and no `Provenance:` line, and an
unticked provenance box on a pull request whose commits are co-authored by
`noreply@anthropic.com` or whose body says "Generated with". It cannot find
generated content that nobody declared. It also refuses a body with no
`Change:` line, or with `Change: <id>` when the pull request's head has no
`changes/<id>/` folder (`Change: none` always passes), and any label set
without exactly one `class:*` label. A pull request opened by a bot
account (a login ending in `[bot]`) skips the `## Checks` and provenance
checks but not the title, `Change:` line or class label, so the bot's
configuration has to supply those: for Renovate, `semanticCommits`,
`labels` and `prBodyNotes`.

When the base branch has a `.github/CODEOWNERS`, the workflow adds the
`protected-path` label to a pull request whose changed files match any of
its patterns, and removes it on a later push that no longer matches. It
reads the base branch's file, as GitHub does, so a pull request cannot
remove its own protection. Without a CODEOWNERS file the label is left to
people. Change footer, class label and protected paths each report as their
own annotation, pass or fail.

A repository adopts it with this caller, saved as
`.github/workflows/pr-checks.yml`:

```yaml
name: pr-checks
on:
  pull_request:
    types: [opened, edited, reopened, synchronize, ready_for_review, labeled, unlabeled]
permissions:
  contents: read
  pull-requests: write
jobs:
  pr-checks:
    uses: blairforce1/.github/.github/workflows/pr-checks.yml@main
```

The check it reports is named `pr-checks / checks`; that is the context a
ruleset lists to make it required. `edited` is in the trigger list so that
fixing the body re-runs the check, and `labeled` and `unlabeled` so that
fixing the class label does. `pull-requests: write` is needed only to add
and remove the `protected-path` label; the workflow cannot run with less
than it declares. On a pull request from a fork the token stays read-only,
and the label step warns instead of labelling. The caller pins `@main`: this
repository's own ruleset guards main, and a fix here reaches every caller
at once. The script is inline in the workflow, so the ref pins rules and
code together.

`tests/pr-checks.test.sh` extracts the script and runs it against
fixtures; `ci.yml` runs the tests and the check itself on every pull
request here.

### security

`.github/workflows/security.yml` scans a pull request with open-source
tools. GitHub code scanning and secret scanning are not available on a
private repository under a Pro account; this is what those repositories
get instead. It is also the server-side backstop for the git hooks, which
an agent session may not skip (pap decision 0005) but a person can. Four
jobs, each its own check:

| Check | What it runs |
|---|---|
| `security / check` | `mise run check` at the repository's own tool pins: every check the hooks run, from the same `.config/mise/conf.d/` fragments, on the whole repository. |
| `security / gitleaks` | `gitleaks git` over the pull request's commits, base to head, with the repository's `.gitleaks.toml`. |
| `security / semgrep` | Semgrep with the community rules for C#, Go, YAML (GitHub Actions, Compose, Kubernetes) and Dockerfiles, from `semgrep/semgrep-rules` at a pinned commit, honouring `.semgrepignore`. |
| `security / trivy` | `trivy fs` for vulnerable dependencies, misconfiguration and secrets, honouring `trivy.yaml`. |

A finding at high or critical fails its check; a lower one is a warning.
Trivy's SARIF level is `error` for HIGH and CRITICAL, Semgrep's for rules
at `ERROR`; gitleaks has no severities, so every secret fails. Every
finding is annotated on the diff and listed in the job summary. On a
public repository, a pull request from a branch of the same repository
also uploads SARIF to code scanning, one category per tool, beside
CodeQL's default setup. A fork's token cannot write security events, so a
fork gets the summary only.

Scanner versions and the rules commit are pinned in the workflow's `env`,
not in the calling repository: every caller scans with the same tools, and
a bump lands once. Every action is pinned by commit. The Semgrep rules are
under the Semgrep Rules License v1.0, which permits scanning your own code.

A repository adopts it with this caller, saved as
`.github/workflows/security.yml`. The pap base template ships it.

```yaml
name: security
on:
  pull_request:
permissions:
  contents: read
  security-events: write
jobs:
  security:
    uses: blairforce1/.github/.github/workflows/security.yml@main
```

`security-events: write` is needed only for the upload, but the reusable
workflow declares it and will not start with less, so a private
repository grants it too. A repository that defines no mise `check` task
fails `security / check` with a message saying so; pass
`with: { mise-check: false }` until it adopts the base layer.

Why not CodeQL: the CodeQL CLI's licence permits it only on open-source
codebases, which rules it out for the private repositories this workflow
exists for. The public ones, this repository and pap, already have CodeQL
through code scanning's default setup, so running it here would duplicate
that.

`ci.yml` calls this workflow from the branch under review, as it does
pr-checks, with `mise-check: false` because this repository has no mise
configuration.

## Verifying inheritance

Pick a private repository with no templates of its own, for example
`blairforce1/journal`.

Issue forms: open `https://github.com/blairforce1/journal/issues/new/choose`.
Intent and Escape are listed, and Blank issue appears only to users with
write access, marked "Maintainers only". This is how inheritance shows for
jenkinsci/docker, which has no templates of its own and lists the three
YAML forms, the contact links, and the security policy from
jenkinsci/.github (observed 2026-09-22). No API reports inherited YAML
forms. The REST community profile leaves `issue_template` null for them,
and GraphQL `issueTemplates` lists Markdown templates only; it returns
nothing for YAML forms even in the repository that holds them. Observed on
supabase, jenkinsci, oven-sh/bun and pnpm/pnpm repositories on 2026-09-22.

Pull request template: the REST community profile answers on private
repositories and names the inherited file.

```sh
gh api repos/blairforce1/journal/community/profile --jq '.files | {issue_template, pull_request_template}'
```

Before this repository exists both fields are null. After it is pushed,
`pull_request_template.html_url` points under
`github.com/blairforce1/.github/` and `issue_template` stays null.

## Validating the issue forms

GitHub publishes no JSON schema for issue forms. SchemaStore's schema
encodes the documented rules and check-jsonschema vendors it:

```sh
uvx check-jsonschema --builtin-schema vendor.github-issue-forms .github/ISSUE_TEMPLATE/intent.yml .github/ISSUE_TEMPLATE/escape.yml
uvx check-jsonschema --builtin-schema vendor.github-issue-config .github/ISSUE_TEMPLATE/config.yml
```

GitHub's own parser runs only once the files are on GitHub. An invalid form
shows an error banner on this repository's issue chooser.
