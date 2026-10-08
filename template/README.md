# {{project-name}}

{{description}}

## First steps

The lock is yours to write, from this machine's uv, and then the first commit -- which `cog check`
(run by `just checks` and by CI) requires to follow
[Conventional Commits](https://www.conventionalcommits.org/). `cargo-generate` made the git
repository; nixpkgs' build of it makes none, so `git init` first if `.git` is missing:

```sh
uv lock
git add .
git commit -m "chore: initial commit from template"
```

With [Nix](https://nixos.org), `nix develop` enters a shell with uv, its Python and every tool
below, at the versions `flake.lock` pins -- the same as the dev group's (`pyproject.toml`).

Then, in whichever order suits you:

- Push to `https://github.com/{{github_username}}/{{project-name}}`.
- Enable the repository settings the auto-merge workflow needs -- they are listed at the top of
  `.github/workflows/dependabot-automerge.yml`. Without required status checks, it merges bumps
  that CI never gated.
- Enable private vulnerability reporting (Settings → Code security): it is off by default, and
  [SECURITY.md](SECURITY.md) and the issue form point to it.
- Add a pending publisher on [PyPI](https://pypi.org/manage/account/publishing/) for
  {% if project_kind == "workspace" %}each package (`{{project-name}}` and `{{project-name}}-core`){% else %}`{{project-name}}`{% endif %}:
  this repository, the workflow `publish.yml`, the environment `pypi`. A release tag then
  publishes without a stored token.
- Run `just checks` once to confirm your tools are complete: a step that stops on a missing
  command names it ([CONTRIBUTING.md](CONTRIBUTING.md) lists them; `nix develop` has them all).
- `just install-hooks`, if you want the lock, ruff, dprint and commit-message checks run by git
  before each commit and push (opt-in, `.githooks/`).
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

```
pyproject.toml                    the workspace: its tool groups and configuration
packages/{{project-name}}/        the command line -- argument handling only
packages/{{project-name}}-core/   the library -- everything worth testing
tests/                            the workspace as a whole
```

Each member is its own distribution, with its own version, changelog and tag
(`<package>-v<version>`): `just release <package> <level>`. A new member is a folder under
`packages/` with its pyproject.toml, README.md and copies of the licence files (its sdist holds
its folder only); the root's tests, ruff's, basedpyright's and coverage's settings name the
members' folders and import names, so add it there too.

{% endif -%}
## Development

This repository uses [`just`](https://github.com/casey/just) to mirror CI locally. `just checks`
runs what the workflows run -- the lock, ruff, the types, dead code, the tests with their
coverage gate, dprint, the commit messages, pip-audit, and last the flake's checks:

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
