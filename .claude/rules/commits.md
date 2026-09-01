---
description: How to choose the type and scope of a commit in this repo, and why the pairing of the two is the release decision.
---

# Commit types and scopes

release-please derives the version bump *and whether a release happens at all* from the commit header, and a release
publishes **both** of this repo's deliverables at once — the workspace image to the registry, and the template to the
live Coder control plane, tagged with the image built by that same release. So the header is a release decision, not a
label.

This repo squash-merges with `squash_merge_commit_title=COMMIT_OR_PR_TITLE`, so a single-commit PR lands its commit
header and a **multi-commit PR lands its PR title**. Both are linted; on a multi-commit branch the title is the string
that survives into `main` and into release-please, so it has to be right on its own.

The header carries two fields answering two questions: **type** is *what kind of change is this?* and **scope** is
*what did it touch?* Never encode "which part of the repo" in the type, or "what kind of change" in the scope. What
carries the release decision is neither field alone but the **pairing rule** between them.

## The delivery boundary

Everything follows from one question, asked of whatever the commit touched:

> **Does this reach a consumer?** Something *ships* if a release puts it in front of one: baked into the image that
> container runtimes pull, or pushed as template HCL that the Coder provisioner applies.

Two consequences that are easy to get backwards:

- **A tool is not shipped because it is pinned.** `mise.toml` and `.pre-commit-config.yaml` pin the *authoring and CI*
  toolchain — including the OpenTofu binary, which never applies this template in production; the provisioner that does
  lives in another repo. The tools a workspace actually gets come from the Dockerfile, from the template's
  `system_packages` parameter, or from the operator's dotfiles. Ask where the pin lives, not what the tool is for.
- **Living under `templates/` is not enough to ship.** `configmap.tf` mounts a specific list of scripts; a file in that
  directory that nothing mounts never reaches a workspace. `script-memory-watchdog-test.sh` is exactly that — CI runs
  it and nothing else does, so it is `internal-workflows`, not `template`.

## Scopes

Closed set. Apply **in order, stopping at the first match** — the ordering is what guarantees every commit lands in
exactly one scope, and it is doing real work in three places flagged below.

| # | Scope | The diff | Ships? |
| --- | --- | --- | --- |
| 1 | `release` | a release cut authored by release-please | — |
| 2 | `renovate` | this repo's Renovate configuration, and nothing else — including a shared-preset pin bump | no |
| 3 | `github-actions` | moves an action `uses:` ref, anywhere, and nothing else | no |
| 4 | `internal-dependencies` | moves any other pinned tool, hook or image version in a file that does not ship — `mise.toml`, `.pre-commit-config.yaml`, `.github/compose/compose.yaml` — and nothing else | no |
| 5 | `internal-workflows` | this repo's own machinery: `.github/workflows/**`, `actions/**`, the disposable test control plane under `.github/compose/**`, `script-memory-watchdog-test.sh`, linter and commitlint configs, release-please config and manifest | no |
| 6 | `image` | `images/**` | **yes** |
| 7 | `template` | `templates/**` | **yes** |
| 8 | `agents` | `CLAUDE.md`, `.claude/**`, anything else written for an AI coding agent | no |
| 9 | *(empty)* | anything else: `README.md`, `DESIGN.md`, `TESTING.md`, repo-root residue — **or** an atomic change spanning both `images/**` and `templates/**` | can ship |

Scopes 1–4 name a kind of *declaration*, so they are location-independent and sort above the footprint scopes. The
three orderings that carry weight:

- **3 and 4 above 5** — an action `uses:` bump inside `.github/workflows/` is `github-actions`, and a Coder or Postgres
  image pin inside `.github/compose/` is `internal-dependencies`. Only *hand-authored* change to those files is
  `internal-workflows`.
- **5 above 7** — `script-memory-watchdog-test.sh` lives under `templates/` and is caught by rule 5 before rule 7 can
  claim it. No exception clause is needed; the order is the mechanism.
- **8 above 9** — agent instructions are internal wherever they sit, so they never fall through to the catch-all.

When a commit spans several surfaces, scope it to the one that **motivated** it — a rule doc, a Renovate rule and a
commitlint change landing together to enforce one vocabulary are `internal-workflows`, because that is where the
enforcement lives. If it genuinely has two motivations, split it. The one span that may not be resolved this way is
shipped-plus-unshipped: see the table at the end.

## Types

Closed set. What matters about a type is not its name but which column it is in.

| Effect | Types | Changelog |
| --- | --- | --- |
| **Forces a release** — patch, or minor for `feat` | `feat`, `fix`, `perf`, `refactor`, `revert` | rendered |
| **No release on its own** | `build`, `chore`, `ci`, `docs`, `style`, `test` | hidden |

A release window containing *only* hidden types produces **no release**: no version bump, no tag, no image rebuild, no
template push. That is deliberate and it is the mechanism this taxonomy rests on. A release here rebuilds the image for
two architectures and pushes the template to production, so a release must mean a shipped artifact actually changed —
otherwise both artifacts are republished byte-identical.

A breaking marker renders and bumps **major regardless of which column the type is in**.

## The pairing rule

| # | Rule | Why |
| --- | --- | --- |
| 1 | `feat`, `fix`, `perf`, `refactor`, `revert` ⇒ scope must be `image`, `template`, or empty | these force a release of *both* deliverables; only a shipped scope can honestly claim that |
| 2 | `chore`, `ci`, `build` ⇒ scope must **not** be `image` or `template` | the converse hazard — a real shipped change typed `chore` is hidden, so it silently never gets published |
| 3 | `docs`, `style`, `test` ⇒ any scope | hidden, and legitimately applicable to a shipped file whose bytes change but whose behaviour does not |

commitlint rejects a violation of rules 1 and 2.

Rule 3 is the one to be careful with. Reach for it only when you can say *why* the shipped behaviour is unchanged. A
"comment-only" edit to a mounted script that turns out to change behaviour needed `fix(template)`.

## Breaking changes

`!` in the header is the marker: `feat(template)!: …`. A footer works only in the full form
`BREAKING CHANGE: <description>` — a bare `BREAKING CHANGE` line with no colon parses as ordinary body text and does
**not** produce a major release.

`!` belongs only on `image`, `template` or the empty scope; rule 1 already enforces that. Nothing unshipped can break a
consumer, so a major bump of a linter or a CI action is `chore`, never breaking. The shared Renovate presets do not
draw that distinction and would mark every major update breaking, so `.github/renovate/scope-internal.json` strips the
marker back off for the unshipped footprints and `scope-shipped.json` restores it for `images/**` and `templates/**`.
That pair of overrides is load-bearing: without it a `tflint` major republishes both deliverables as a new major
version.

## Cases that would otherwise be guessed

| Situation | Header |
| --- | --- |
| Diff spans a shipped and an unshipped surface — a template script and the workflow that tests it | **Split the PR.** One scope per PR; the squashed header is a claim about the whole diff and there is no honest single scope for that one |
| Diff genuinely spans `images/**` and `templates/**` and cannot be split — a baked tool and the mounted script calling it | empty scope, both named in the subject. This is the only legitimate use of an empty scope for a release-forcing type |
| Bumping Coder or Postgres in the disposable test control plane | `chore(internal-dependencies)` — a pinned image in a file that does not ship |
| Hand-editing `compose.yaml`'s service topology rather than a pin | `ci(internal-workflows)` — rule 4 covers version moves only |
| Bumping the OpenTofu pin in `mise.toml` | `chore(internal-dependencies)`. The binary that applies the template in production belongs to the provisioner, in another repo |
| Bumping an OpenTofu **provider** in `terraform.tf` / `.terraform.lock.hcl` | `fix(template)` or `feat(template)` — the provider requirement is HCL that gets pushed |
| Adding a package to the image | `feat(image)` for a new tool, `fix(image)` for a corrected or repinned one |
| Adding a package to the template's `system_packages` parameter default | `feat(template)` — it ships as template HCL |
| Editing a comment inside a mounted template script | `docs(template)` if behaviour is provably unchanged; otherwise it was never comment-only |
| Editing `DESIGN.md`, `TESTING.md`, `README.md` | `docs:` — empty scope, hidden, no release. A doc fix must not cost an image rebuild |
| Editing `CLAUDE.md` or anything under `.claude/` | `docs(agents)` |
| Changing a Renovate rule that alters which scope the bot emits | `chore(renovate)`, and update `scope-enum` in the **same** commit |
| A `revert` | takes the scope of the commit it reverts, and is release-forcing — reverting a shipped change must republish |
| Renovate and release-please headers | leave them alone; they are asserted by this repo's `packageRules` and by the release PR title pattern |

## Keeping the bot inside the enum

Renovate authors most commits here, so the enum is only as good as what the bot can emit. Two invariants make that
hold; both are properties to re-check, not lists to maintain.

- **`github-actions` and `internal-dependencies` are emitted by the shared presets**, so those two scopes are inherited
  rather than asserted locally. That is why the preset pin and this enum have to move together: a rename upstream lands
  here as a rejected header. Before bumping the pin, diff the preset's `semanticCommitScope` values against
  `scope-enum` and move the enum **first**.
- **Local rules claim scope by `matchFileNames`, never by manager or dependency class.** Scope is then a function of
  the footprint. This matters because a *grouped* branch takes its scope from whichever upgrade sorts first; a scope
  keyed on dependency class would be decided by branch composition, which is repo state, not config. `images/**` and
  `templates/**` are matched with no manager filter for the same reason — a new manager appearing in a shipped tree is
  scoped correctly with no config change.

`semanticCommitScope` is not the only scope-carrying field. `commitMessagePrefix` embeds a whole header, and
release-please composes its own PR title from `pull-request-title-pattern`. An audit reading only
`semanticCommitScope` is checking a subset of the emitters.

Anything no rule claims falls to the fallback in `.github/renovate/scope-fallback.json`, which emits
`chore(internal-dependencies)`. That is sound rather than merely safe: the two shipped trees are matched by
whole-subtree globs, so an uncovered dependency site is necessarily outside both and *is* an internal dependency.
