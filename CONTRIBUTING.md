# Contributing to Todori

Thank you for considering a contribution to Todori. This document summarizes the essentials for contributing.

## License

Todori is licensed under **AGPL-3.0-only** (see [`LICENSE`](./LICENSE)). By contributing, you agree that your contribution is licensed under the same terms.

## Contributor License Agreement (CLA)

All pull requests require agreement to the [Contributor License Agreement](./CLA.md). By opening a pull request, you agree to its terms unless otherwise arranged with the maintainers. The CLA grants the Project owner the additional rights needed to redistribute the Project under other terms where necessary (e.g. app store distribution), while you retain copyright ownership of your contribution.

## Quality Gates

Before opening a pull request, make sure the following all pass locally:

- `cargo fmt --all -- --check`
- `cargo clippy --workspace -- -D warnings`
- `cargo test --workspace`
- `cd app && flutter analyze` (if you changed anything under `app/`)

Pull requests that fail these checks in CI will not be merged until fixed.

## Commit Messages

This repository follows [Conventional Commits](https://www.conventionalcommits.org/) (e.g. `feat:`, `fix:`, `docs:`, `chore:`). Commit messages may be written in English or Japanese.

## Getting Started

See [`README.md`](./README.md) for the repository structure and development commands.
