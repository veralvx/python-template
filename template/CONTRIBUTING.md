# Contributing to `{{project-name}}`

Thank you for considering contributing to `{{project-name}}`!

## Prerequisites

Either **Nix** -- `nix develop` gives every tool below at the versions `flake.lock` pins, uv on
nixpkgs' Python {{python_min}} (its own downloads off) -- or, installed yourself:

- **[uv](https://docs.astral.sh/uv/) 0.11.21**, exactly: `pyproject.toml`'s `required-version`,
  which writes and checks the lock. `uv sync --locked` then installs the dev group -- ruff,
  basedpyright, ty, vulture, pytest and its plugins -- at the pinned versions.
- **[just](https://github.com/casey/just)** -- the command runner the automation is written in.
- **[dprint](https://dprint.dev/)** -- formats the Markdown and TOML.
- **[cocogitto](https://docs.cog.tools/)** (`cog`) -- enforces Conventional Commits.
- **[Nix](https://nixos.org)** for the last of `just checks`, the flake's checks (`just nix`):
  without it, `just checks` stops there, every other check passed.

pip-audit and git-cliff need no install: `just audit` and `just changelog` run them from their
own dependency groups, through uv.

On NixOS, the wheels' executables (ruff, ty, git-cliff, basedpyright's node) need a standard
dynamic loader: `programs.nix-ld.enable = true;`.

## Setup

1. Fork this repository and create your branch from `main`.
2. Clone your fork, and install the environment:

```sh
git clone https://github.com/<you>/{{project-name}} && cd {{project-name}}
uv sync --locked
```

3. Optionally, `just install-hooks`: `.githooks/` then checks the lock, ruff and dprint before
   each commit, the message as a Conventional Commit, and every pushed commit's message before a
   push -- what CI would refuse, minutes earlier. They need `just`, `uv`, `dprint` and `cog` on
   `PATH` (inside `nix develop`, with Nix); `git config --unset core.hooksPath` turns them off.

## Guidelines

Before you start, read [AGENTS.md](AGENTS.md). It documents the lint and type policy -- which
rules are on, why, and what to do when one fires -- and applies to human and AI-assisted
contributions alike.

## Testing Strategy

- **Pure functions:** isolate logic from side effects wherever possible and cover it with unit
  tests.
- **Regressions:** if you are fixing a bug, include a test that reproduces the previous failure
  state.
- **Coverage:** every line and branch (`fail_under = 100`). Code a test cannot reach is
  questioned before it is excluded.
{%- if project_kind == "workspace" %}
- **Where logic goes:** in `packages/{{project-name}}-core`, not in the command line, which
  parses arguments and prints.
{%- endif %}
- **The tests import the package as installed** (pytest's `--import-mode=importlib`): the editable
  install here, the built one in the flake's checks -- so a file missing from the wheel fails
  there.
- **Property tests** (Hypothesis), if you add them: `uv add --dev 'hypothesis==<version>'`, at
  the flake's nixpkgs' version, and a `conftest.py` at the repository's root -- every run loads
  it; add it to `[tool.basedpyright]`'s `include` -- loading Hypothesis's own `ci` profile:

  ```python
  """Hypothesis's `ci` profile in every run, the Nix sandbox's included."""

  from hypothesis import settings

  settings.load_profile("ci")
  ```

  It draws the same examples each run, with no example database and no deadline; Hypothesis
  loads it by itself only under a CI's variable (`CI`, `GITHUB_ACTIONS`...), so the flake and a
  local run would draw anew.

## Development Workflow

1. The [Conventional Commits](https://www.conventionalcommits.org/) specification is enforced on
   every commit. A commit's subject is its changelog entry -- git-cliff writes the changelog from
   them at each release -- so write it for the package's users.
2. Run the checks. The `justfile` runs the workflows' commands:

```sh
just checks   # the lock, ruff, types, dead code, the tests, dprint, cog, pip-audit, then `just nix`
just nix      # the flake's checks alone, as nix.yml: git's files only -- `git add` a new one
just format   # ruff and dprint, in place
just build    # every package's sdist and wheel, into dist/
```

`just` alone lists every recipe.

A new dependency: `uv add` it. The flake builds with nixpkgs' package of the same name; `just nix`
names one it cannot map -- another name in nixpkgs, extras, a marker -- to give in
`nix/packages.nix`'s `overrides`. A new dev tool: `uv add --dev 'name==<version>'`, the flake's
nixpkgs' version (its `pins` check holds it); a Python package there -- a pytest plugin, say --
joins the flake's test environment too.

## Creating a Pull Request

1. Make sure `just checks` passes.
2. Open a pull request against `main`, titled as a conventional commit: a squash merge makes the
   title its commit, and so a changelog entry (CI checks it). Describe the problem it solves, and
   link its issue (`Fixes #123`), if any.
3. Wait for a maintainer's review.

## Releasing (maintainers)

{% if project_kind == "workspace" -%}
Each package is released on its own, from a clean `main` equal to `origin/main`, CI green on it:

```sh
just changelog <package> --unreleased   # the section the release will write
just release <package> <major|minor|patch>
```

The tag is `<package>-v<version>`. Release `{{project-name}}-core` first when `{{project-name}}`
needs its new version, and raise `{{project-name}}`'s requirement on it to that version: uv and
the flake build against the workspace's copy, so nothing here sees a stale floor -- PyPI's users
would.
{%- else -%}
From a clean `main` equal to `origin/main`, CI green on it:

```sh
just changelog --unreleased   # the section the release will write
just release <major|minor|patch>
```

The tag is `v<version>`.
{%- endif %}

The recipe shows every step, in order, and runs no tests -- CI's verdict on that commit is the
release's: it refuses a release with nothing in it, sets the version (`uv version --bump`, the lock
with it), writes the changelog (git-cliff), commits, tags, and pushes the commit and the tag
together. The first release is the version `pyproject.toml` declares, whatever the level. The tag
runs `publish.yml`: the package built once, published to PyPI by Trusted Publishing, then its GitHub
release of the same files, its notes the changelog's new section (a dev or pre-release version, a
GitHub pre-release)
{%- if project_kind != "lib" and container_image %};
the command's, `image.yml` too (its OCI image to GHCR, from the flake's `image`: `nix build
.#image` builds it here){% endif %}.

- The commits since the last tag must hold a change a user meets (`feat`, `fix`, `perf`,
  `build`...): `chore`, `ci` and `style` alone make no release.
- The release pushes to `main` directly: with "Require a pull request before merging" on, the
  maintainer cutting it needs the rule's bypass. A refused push leaves the commit and the tag
  local -- push them again with `git push --atomic origin main <tag>` once allowed.

## Updating the tools

The dev group's pins are the flake's nixpkgs' versions, so a tool moves with nixpkgs:
`nix flake update`, then `nix flake check` -- its `pins` check names each pin to move, to the
version it gives -- then `uv lock` and `just checks`. A new ruff or basedpyright brings new rules;
read them before silencing any.
