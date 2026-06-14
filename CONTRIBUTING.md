# Contributing

Thanks for taking the time to contribute!

## Development

The application is a set of Bash scripts plus `vsftpd`/`supervisord` config,
packaged in a Docker image. A `Makefile` wraps the common tasks (each runs in
Docker, so the only requirement is Docker itself):

```bash
make help    # list targets
make lint    # shellcheck + hadolint
make test    # run the bats suite
make build   # build the image
```

CI runs ShellCheck, Hadolint, the bats tests, an image build and a Trivy scan on
every pull request.

## Commit messages — Conventional Commits

This project releases automatically with
[semantic-release](https://semantic-release.gitbook.io/), so commit messages
**must** follow the [Conventional Commits](https://www.conventionalcommits.org/)
format:

```
<type>[optional scope]: <description>
```

Common types and how they affect the next version:

| Type | Example | Release |
| --- | --- | --- |
| `feat` | `feat: add SFTP-only mode` | minor |
| `fix` | `fix: mount over non-empty directory` | patch |
| `perf` / `refactor` / `build` / `revert` | `refactor: simplify user setup` | patch |
| `docs` / `chore` / `ci` / `test` / `style` | `docs: clarify PASV setup` | none |

A breaking change — either `type!: ...` or a `BREAKING CHANGE:` footer — triggers
a **major** release.

A CI check (`PR title`) validates that every pull-request title is a valid
Conventional Commit. **Squash-merge** pull requests so the title becomes the
commit subject on `master`; that is what the release automation reads.

## Releases

Releases are not cut on merge. A scheduled workflow runs once a day; when there
are new releasable commits on `master`, it tags the next semantic version,
publishes a GitHub Release, and pushes the image to GHCR. See
[`.github/workflows/release.yml`](.github/workflows/release.yml).
