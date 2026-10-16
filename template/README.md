# {{project-name}}

{{description}}

## First steps

The lock is yours to write, from this machine's uv, and then the first commit -- which `cog check`
(run by `just checks` and by CI) requires to follow
[Conventional Commits](https://www.conventionalcommits.org/). `cargo-generate` made the git
repository; nixpkgs' build of it makes none, so `git init -b main` first if `.git` is missing:

```sh
uv lock
git add .
git commit -m "chore: initial commit from template"
```

With [Nix](https://nixos.org), `nix develop` enters a shell with uv, its Python and every tool
below, at the versions `flake.lock` pins -- the same as the dev group's (`pyproject.toml`). A
flake sees git's files only, so add them first: `git add . && nix develop --command uv lock`, then
the commit.

Then, in whichever order suits you:

- Push to `https://github.com/{{github_username}}/{{project-name}}`.
- Enable the repository settings the auto-merge workflow needs -- they are listed at the top of
  `.github/workflows/dependabot-automerge.yml`. Without required status checks, it merges bumps
  that CI never gated.
- Enable private vulnerability reporting (Settings → Code security): it is off by default, and
  [SECURITY.md](SECURITY.md) and the issue form point to it.
- Add a pending publisher on [PyPI](https://pypi.org/manage/account/publishing/) for each
  package: this repository, the workflow `publish.yml`, the environment `pypi`. A release tag
  then publishes without a stored token, and its GitHub release follows PyPI's: without the
  publisher, neither is made. {% if project_kind == "workspace" %}The packages are
  `{{project-name}}` and `{{project-name}}-core`.{% else %}The package is `{{project-name}}`.{% endif %}
- If you limit the `pypi` environment's deployments (Settings → Environments), admit the release
  tags, each a rule of ref type Tag -- {% if project_kind == "workspace" %}`{{project-name}}-v*`
  and `{{project-name}}-core-v*`{% else %}`v*`{% endif %}: the PyPI job runs on the tag, and an
  environment that refuses it publishes nothing.
{%- if project_kind != "lib" and container_image %}
- After the first release, make the image public: GHCR publishes a new package as private (its
  page, Package settings → Change visibility).
- To publish the image to Docker Hub too: create its repository there, then set the repository
  variable `DOCKERHUB_USERNAME` and the secret `DOCKERHUB_TOKEN` (an access token that writes)
  -- and the variable `DOCKERHUB_REPOSITORY` (`namespace/name`) unless it is
  `<username>/<this repository's name>`. A Docker Hub failure holds the GHCR release back too.
{%- endif %}
- Run `just checks` once to confirm your tools are complete: a step that stops on a missing
  command names it ([CONTRIBUTING.md](CONTRIBUTING.md) lists them; `nix develop` has them all).
- `just install-hooks`, if you want the lock, ruff, the shell, the workflows, dprint and
  commit-message checks run by git before each commit and push (opt-in, `.githooks/`).
- Read [AGENTS.md](AGENTS.md) before writing code: every ruff rule is on, and basedpyright runs
  in its strictest mode.

## Requirements

Python {{python_min}} or later.

## Install
{% if project_kind == "lib" %}
```sh
uv add {{project-name}}
```
{% elsif project_kind == "workspace" %}
```sh
uv tool install {{project-name}}
```

The library alone:

```sh
uv add {{project-name}}-core
```
{% else %}
```sh
uv tool install {{project-name}}
```
{% endif %}
With Nix, `nix {% if project_kind == "lib" %}build{% else %}run{% endif %} github:{{github_username}}/{{project-name}}`.
{%- if project_kind != "lib" and container_image %}

As an OCI image, for Linux on amd64 and arm64:

```sh
docker run --rm ghcr.io/{{ github_username | downcase }}/{{project-name}} --version
```
{%- endif %}

## Usage
{% if project_kind == "lib" %}
```python
from {{crate_name}} import greeting

assert greeting("Ada") == "Hello, Ada!"
```
{% elsif project_kind == "workspace" %}
```sh
{{project-name}} Ada
```

The logic lives in `{{project-name}}-core`, usable on its own:

```python
from {{crate_name}}_core import greeting

assert greeting("Ada") == "Hello, Ada!"
```
{% else %}
```sh
{{project-name}} Ada
```

or, as a library:

```python
from {{crate_name}} import greeting

assert greeting("Ada") == "Hello, Ada!"
```
{% endif %}
{% if project_kind == "workspace" -%}
## Layout

- `pyproject.toml` -- the workspace: its tool groups and configuration
- `packages/{{project-name}}/` -- the command line: argument handling only; the main package
  (`[tool.{{project-name}}] main = true`), the flake's default, its image and the latest release
- `packages/{{project-name}}-core/` -- the library: everything worth testing
- `tests/` -- the workspace as a whole

Each member is its own distribution, with its own version, changelog and tag
(`<package>-v<version>`): `just release <package> <level>`. A new member is a folder under
`packages/` with its pyproject.toml, README.md, `src/` and copies of the licence files (its sdist
holds its folder only); the root's ruff, basedpyright, pytest and coverage settings name the
members' folders and import names, so add it there too (`tests/test_workspace.py` checks it). A
requirement on another member needs `[tool.uv.sources] <name> = { workspace = true }` too: without
it, uv refuses to lock.

{% endif -%}
## Development

This repository uses [`just`](https://github.com/casey/just) to mirror CI locally. `just checks`
runs what the workflows run -- the lock, ruff, the shell, the workflows, the types, dead code, the
tests with their coverage gate, dprint, the commit messages, pip-audit, and last the flake's
formatter and checks:

```sh
just checks
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the tools those checks need and how a release is cut,
and [AGENTS.md](AGENTS.md) for the lint and type policy and what to do when a rule fires.

## License
{% if license == "MIT OR Apache-2.0" %}
Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
  <http://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or <http://opensource.org/licenses/MIT>)

at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in
the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without
any additional terms or conditions.
{%- elsif license == "MIT" %}
Licensed under the MIT license ([LICENSE-MIT](LICENSE-MIT) or
<http://opensource.org/licenses/MIT>).
{%- else %}
Licensed under the Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
<http://www.apache.org/licenses/LICENSE-2.0>).
{%- endif %}
