# TESTING.md

How changes to the template or image get verified before they can affect production. There's no separate test suite or staging environment (see [DESIGN.md](DESIGN.md)) — verification is the release pipeline itself, run in a mode that exercises everything a real release would except the parts that would affect the live template or its persistent state.

## Intent

A change to `templates/**` or `images/**` isn't trustworthy just because it parses (that's what lint/`terraform validate` already cover — see [CLAUDE.md](CLAUDE.md)). It's trustworthy once the same pipeline that would ship it has actually built the image and applied the template against the real cluster and provider. The test workflow's job is to make that possible on every PR, automatically, without any risk to the production template or the shared persistent state real workspaces depend on.

## How it works

The release pipeline (`.github/workflows/release.yaml`) runs in one of two modes, gated by whether it's allowed to publish for real:

- **Dry-run mode** — automatic on any PR touching `images/**`, `templates/**`, or the release config itself, and available on demand via manual dispatch.
- **Live mode** — runs on merge to `main`.

Both modes run the identical sequence of stages; only what each stage is permitted to do at the end differs.

## What each stage confirms

1. **Versioning** — commit history since the last release is parsed to determine what the next version would be. In dry-run this stops short of tagging or publishing; it still confirms the commit history is well-formed enough to produce a valid release.
2. **Image build** — the container image is built for every published architecture and pushed to the registry. This is the same build a live release performs, so it confirms the Dockerfile still produces a working image end to end — dry-run only changes the tag it's pushed under, not the build itself.
3. **Template push** — the Terraform template is applied against the real Coder deployment and Kubernetes cluster, using the image just built. This confirms the template is actually valid against live provider/cluster state, not just internally consistent. Dry-run redirects this push to a separate, clearly-named template rather than the one real workspaces use, and backs it with disposable storage instead of the shared persistent volume — so nothing here can affect an existing workspace no matter what the change does.

Because all three stages run for real in dry-run — just scoped away from production — a passing PR is a meaningful signal that a live release would also succeed, not a guess based on static checks alone.

## After merge

Merging to `main` is what flips the pipeline into live mode — there's no separate promotion step afterward. The dry-run pass on the PR is the actual release gate.
