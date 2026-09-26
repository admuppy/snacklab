# Contributing to SnackLab

Thanks for your interest! Issues and pull requests are welcome.

## Ways to contribute

- **Content** (most wanted): new modules or tracks, fixes to existing checks/guides,
  and **translations** of guides and grading messages.
- **Portal / chart**: bug fixes, portability improvements (new CNIs, storage backends,
  registries, architectures), the planned Docker Compose deployment.
- **Docs**: installation reports for environments not yet listed in the README.

## Development setup

```bash
cd v0.1
DRIVER=sim node server.js     # Node.js >= 18, no npm install needed
```

The `sim` driver fakes learner sessions so you can develop the UI and content without a
cluster. For real-session work you need a Kubernetes cluster that allows privileged
pods — see the README.

## Content contributions

Read [docs/content-authoring-conventions.md](docs/content-authoring-conventions.md)
first. In short, a module is:

```
meta.json  guide.md (+ guide.<locale>.md)  bootstrap.sh  checks/*.sh  solution.sh
checks/messages.json          # localized check messages, scripts print keys only
explain.md                    # exam-style modules only
```

Before opening a PR, validate your module end-to-end in a real learner pod:

```bash
./deploy/e2e-course.sh courses/<course> [module-id]
```

The E2E flow asserts: bootstrap succeeds → all checks FAIL pre-solution →
`solution.sh` runs → all checks PASS.

## Code conventions

- Comments in **English** for all new and modified code.
- The portal is deliberately dependency-free (single `server.js`, no npm packages).
  PRs adding runtime dependencies need a strong justification.
- Chart changes must pass `helm lint chart` and render with default values
  (`helm template lab chart`).

## Commit / PR

- Keep PRs focused; one topic per PR.
- Describe what you tested (E2E output, cluster/distro used) in the PR body.

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE).
