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
  repository. Starter workflows in `workflow-templates/` are an organisation
  feature and do not apply to a personal account.

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
