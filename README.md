# python-template

A [`cargo-generate`](https://github.com/cargo-generate/cargo-generate) template for a Python
project on [uv](https://docs.astral.sh/uv/) that starts with the whole toolchain wired up: every
ruff rule and basedpyright's strictest mode, tests with a 100% coverage gate, GitHub Actions CI on
every supported Python, Conventional Commits, changelogs by git-cliff, a release recipe that shows
every step, publishing to PyPI by Trusted Publishing, dependency auditing, a Nix flake whose tools
are the dev group's, and a `justfile` that runs locally what CI runs remotely.

It is the [rust-template](https://github.com/veralvx/rust-template)'s counterpart, with what
[ffsuite](https://github.com/veramachine/ffsuite)'s setup taught. See [Attribution](#attribution).

## Usage

```sh
cargo install --locked cargo-generate   # 0.25 or later (the template refuses older)
cargo generate --git https://github.com/veralvx/python-template template
```

cargo-generate is language-agnostic: Liquid over files, with conditionals; nothing here is Rust.
nixpkgs 26.05 carries cargo-generate 0.23.9, below the floor -- install it with cargo. A build
without its `git` feature (nixpkgs' are) makes no repository: `git init -b main` in the new
project.

The trailing `template` is the sub-folder that holds the template; the repository root holds
this README and the template's own CI.

Everything can be answered non-interactively, which is what the smoke test does:

```sh
cargo generate --git https://github.com/veralvx/python-template template \
  --name my-project --silent \
  -d project_kind=workspace \
  -d description="Does a thing." \
  -d author_name="Jane Doe" \
  -d author_email=jane@example.com \
  -d github_username=jane \
  -d license="MIT OR Apache-2.0" \
  -d python_min=3.13 \
  -d keywords="cli, parser"
```

Then, in the new project, the first steps its README gives: `uv lock`, the first commit.

### If generation fails

`cargo-generate` creates the destination directory *before* it validates any answer, and leaves
it behind when validation rejects one. The retry then stops with
`Target directory already exists, aborting!` -- remove the empty directory and try again.

## What you are asked

| Prompt            | Default             | Goes into                                                         |
| ----------------- | ------------------- | ----------------------------------------------------------------- |
| *(project name)*  | —                   | distribution name, command, import name (`-` as `_`), repository  |
| `description`     | `A Python package.` | `project.description`, README, the flake's `description`          |
| `project_kind`    | `bin`               | `bin`, `lib` or `workspace` -- see below                          |
| `author_name`     | —                   | `project.authors`, the licence's copyright line                   |
| `author_email`    | *(empty)*           | `project.authors`, code of conduct -- omitted if blank            |
| `github_username` | —                   | the repository's URLs, security advisory link                     |
| `license`         | `MIT OR Apache-2.0` | `project.license`, which `LICENSE-*` files are kept, README       |
| `python_min`      | `3.13`              | `requires-python`, `.python-versions`, classifiers, ruff, pyright |
| `keywords`        | *(empty)*           | `project.keywords` (comma-separated)                              |
| `container_image` | `true` (not `lib`)  | the flake's `image` and `image.yml` -- see below                  |

Every answer is validated at the prompt: the description, the author and the email cannot hold a
`"` or `\` (they land in TOML strings), nor the description a `$` (it lands in a Nix string). The
project name is checked before anything is written (`template/validate-name.rhai`, a pre hook):
its import name must be an ASCII Python identifier, no keyword and no standard-library
module's: `3d-tool`, `async` or `calendar` is refused.

`container_image` is asked for `bin` and `workspace` alone: a library has no command to run.

### What `project_kind` selects

| Value       | Layout                                                                                                                                                            |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bin`       | one package, `src/<name>/`: a library and its command line (`[project.scripts]`)                                                                                  |
| `lib`       | one package, `src/<name>/`: a library                                                                                                                             |
| `workspace` | a uv workspace: `packages/<name>-core` (the library) and `packages/<name>` (the command line using it), each its own distribution, version, changelog and release |

The workspace's root is uv's virtual root: no `[project]` of its own, the tool groups and the tools'
configuration for every member. A member's requirement on another (`<name>-core>=0.1.0`) is resolved
from the workspace by uv (`[tool.uv.sources]`) and from PyPI by anyone else;
`tests/test_workspace.py` refuses a range the other member's version falls outside, and a member
whose licence texts differ from the root's -- an sdist holds the member's folder alone. One member
is the main package, `<name>`, marked in its own pyproject.toml (`[tool.<name>] main = true`: a
`tool.<name>` table is `<name>`'s owner's, PEP 518): the flake's default, the image's command and
GitHub's latest release; another member's tag makes no image, a command of its own or not. A single
package is its own main package.

### The Pythons

`python_min` is the floor; every newer one up to 3.14 is supported, listed once in
`.python-versions`. CI's matrix reads that file at run time, and the flake runs the tests and
the types on each, against nixpkgs' interpreters. A new Python is a line there, a classifier,
and (here) a choice and a line in `template/.python-versions`.

### The OCI image

With `container_image`, the flake has an `image` on Linux: `dockerTools.buildLayeredImage` of the
main package's command -- its closure alone, no base image and no `/bin/sh`, run as `nobody`,
labelled for GHCR. `nix build .#image` gives the gzipped docker-archive and the flake's checks build
it; `.#image.stream` streams it uncompressed, sparing the store a second copy of the closure.
`image.yml`, on the main package's release tag, streams it into Docker on amd64 and arm64, runs it,
pushes each, and joins them as `ghcr.io/<owner>/<repository>:<version>` (`latest` too while it is
the main package's highest release), with the job's token -- and to Docker Hub too, under the same
tags, once the variable `DOCKERHUB_USERNAME` and the secret `DOCKERHUB_TOKEN` are set
(`.github/image-registries.sh`; a Docker Hub failure holds the GHCR release back too); run by hand,
it builds and runs the image on both, pushing nothing (on a tag, it publishes that release again).
The image holds no CA certificates: Python's `ssl` verifying against the system's needs `contents =
[ pkgs.cacert ]` and `SSL_CERT_FILE` in `config.Env`.

## What you get

```
pyproject.toml        the project (or the workspace), the pinned dev group, every tool's config
.python-versions      the supported Pythons, one a line: CI's matrix, the flake's checks
uv.lock               written by the first `uv lock`, committed; `--locked` everywhere after
justfile              `just checks` = what CI runs, the flake's checks last; `just format`,
                      `just release`
flake.nix, nix/       the dev shell, `nix fmt`, the packages, the checks, the image (if chosen);
                      flake.lock pins nixpkgs 26.05
.githooks/            opt-in (`just install-hooks`): the lock, ruff, the shell, the workflows,
                      dprint before a commit; Conventional Commits for the message and the push
.editorconfig         shfmt's style, for the shell scripts and the git hooks
cliff.toml, cog.toml  git-cliff changelogs, cocogitto's commit checks
dprint.json           Markdown and TOML formatting, plugins at their latest
src/, tests/          starter code: typed, documented, every line and branch tested
                      (a workspace puts these under packages/<name>/ and packages/<name>-core/)
AGENTS.md             the lint and type policy, and what to do when a rule fires
README, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT
LICENSE-MIT / LICENSE-APACHE (a workspace member carries its own copies)
.github/              8 workflows (9 with the image), dependabot, issue and PR templates,
                      the tag, release-notes (and image registries) scripts
```

### The tools, pinned to nixpkgs

The dev group's tools are exact pins (`ruff==0.15.14`, `basedpyright==1.39.3`, `pytest==9.0.3`
...), each the version the flake's nixpkgs carries, and `required-version` pins uv itself. So
`uv run` (and CI) and `nix flake check` judge the code with the same tools: with floors, the lock
took newer releases, and a new ruff rule or stub disagreed with Nix's verdict on the same code
(measured, in ffsuite). The flake's `pins` check holds them: a `nix flake update` that moves a
tool names each pin to move. That is also why the template ships its `flake.lock`, unlike the
rust-template: the pins are only right for the nixpkgs they were taken from.

### The CI workflows

- `checks.yml` -- the lock, ruff (lint and format), basedpyright, ty (advisory), vulture, and
  pytest with its coverage gate, on every Python `.python-versions` lists.
- `nix.yml` -- `nix fmt -- --ci` (nixfmt, shfmt and just's own, through treefmt: it formats, and
  fails if that changed a file), then `nix flake check`, on x86_64 Linux, aarch64 Linux and Apple
  silicon: the tests and the types on every Python against the built packages, ruff, the format, the
  shell (`just shell-check`: shellcheck and shfmt over the scripts, the hooks and the justfile's
  script recipes), the workflows (actionlint), dead code, the pins, and the command run through its
  wrapper; every system also evaluated.
- `security.yml` -- pip-audit over the exported lock, daily and when the lock changes.
- `dependency-review.yml` -- licence and advisory review on pull requests.
- `style-check-dprint.yml`, `style-check-cocogitto.yml` -- formatting, and Conventional Commits:
  every commit, and a pull request's title (a squash merge makes it the commit).
- `publish.yml` -- a release tag builds its package once, publishes it to PyPI by Trusted
  Publishing (no token stored; attestations), then makes the GitHub release of the same files,
  the changelog's section as notes. Only the PyPI job can mint a token; only the release job can
  write.
- `image.yml` (with the image) -- the main package's release tag pushes its OCI image to GHCR (and
  Docker Hub, given its secrets), for amd64 and arm64, after running it; by hand on a branch, a
  rehearsal that pushes nothing.
- `dependabot-automerge.yml` -- merges Dependabot's patch and minor action bumps once the
  required checks pass. Read its setup comment: without required checks it merges what CI never
  gated.

Every action is pinned to a commit, its version in a comment; Dependabot moves them -- in this
repository too, the template's workflows with this repository's, in one pull request
(`.github/dependabot.yml`). It watches the actions only: the dev group's pins move with nixpkgs,
and pip-audit watches the lock.

### The changelog and `just release`

There is no `CHANGELOG.md` until the first release writes one: git-cliff generates it from the
commits, never a hand; a workspace member's from the commits touching its folder.
`just release [package] <major|minor|patch>` shows every step in order, none hidden in a hook or
another tool's config, and runs no tests -- it releases `origin/main`, which CI checks: it refuses a
dirty tree, another branch, a `main` that is not `origin/main` or a release with nothing in it; in a
workspace (step 4), a member ahead of any it needs, directly or through another -- one whose `src`
or installed fields changed since its release, a release not on PyPI, a requirement below one -- and
a library version its dependent's range excludes; sets the version (`uv version --bump`, the lock
with it -- the first release is the declared version, whatever the level); writes the changelog;
commits; tags `v<version>` (a member's `<package>-v<version>`); pushes the commit and the tag
atomically. If a step fails before the commit -- a git hook refusing it, say -- it puts the files
back.

## Developing this template

The repository is a project of its own around `template/`, with the files a generated project
has, adapted: [CONTRIBUTING.md](CONTRIBUTING.md) (the tools, the release), [AGENTS.md](AGENTS.md)
(the rules), [SECURITY.md](SECURITY.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), a `justfile`,
the git hooks, `dprint.json`, `cog.toml` and `cliff.toml` (the changelog), `.editorconfig`, a
flake and its lock (the tools' shell, `nix fmt`, the checks), issue and pull request templates.
Some are the template's own files, copied: render-check holds each copy to its original.

```sh
nix develop               # every tool below (or CONTRIBUTING.md's list, installed yourself)
just checks               # render-check, the shell, the workflows, dprint, cog, the flake's last
just smoke workspace      # generated by cargo-generate, then its own `just checks` (each kind)
just generate bin         # into target/bin/demo, to look at
just format               # every formatter the checks hold the files to, `nix fmt` last
```

`just render-check` installs `tools/requirements.txt` into `.venv` (Python 3.11+, for tomllib) and
runs `tools/render-check.py`, which renders every templated file for all 108 combinations of
`project_kind` (with the image or without; a lib with it unasked, or given anyway) × `license` ×
`python_min` × empty-or-present email and keywords, then checks that nothing is left unexpanded and
that the result parses as TOML, YAML, JSON and -- with `nix-instantiate` on `PATH` -- Nix. It also
guards what fails silently otherwise:

- **Every referenced variable is declared.** cargo-generate renders an unknown variable as an
  empty string, and a file it cannot render at all as it stands, without a word (0.25,
  measured: Liquid's `include` is one such) -- no "leftover `{{`" check sees either.
- **No file on the `exclude` list contains a placeholder**: those are copied verbatim -- the
  workflows (GitHub's `${{ }}`), the justfile (just's `{{ }}`), cliff.toml (Tera, which Liquid
  would evaluate silently), the Nix files and the hooks.
- **Every `ignore` entry is a literal path that exists.** `ignore` is not glob-matched, and
  removes paths before rendering, so an entry spells a path as the template does.
- **The copies agree.** Liquid has no includes here, so the workspace members repeat the single
  package's code, manifest table and licence texts; the check holds them equal, but for what
  tells them apart.
- **The manifests describe their layout**: `.python-versions`, `requires-python`, the
  classifiers, ruff's and basedpyright's targets, the licence files, the kind; and the image's
  Nix file, workflow and flake output, all present or all absent.
- **The copies are the template's**: `cog.toml`, `cliff.toml`, `.editorconfig`, the release-notes
  script, two hooks and three workflows byte for byte (and executable alike), the justfiles'
  `shell-check`, `shfmt` and `shfmt-recipes` recipes, and dprint's plugins.

The rest of `just checks`: `just shell-check` (shellcheck and shfmt over every shell script, the
hooks and this justfile's script recipes) and `just template-shell-check` (the template's, its
justfile's recipes included); actionlint over both sets of workflows; dprint over this repository's
Markdown and TOML (`template/` is the generated projects'); `cog check`; and `just nix` --
`nix fmt -- --ci` (nixfmt, shfmt and just's own, through treefmt; it formats, and fails if that
changed a file) and the flake's checks, which run the shell and actionlint again in the sandbox.

CI runs them: `nix.yml` the flake (`just nix`, step by step), `style-check-dprint.yml` and
`style-check-cocogitto.yml` dprint and the commits, `dependabot-automerge.yml` Dependabot's action
and render-check bumps, `release.yml` a release tag's GitHub release (`just release` cuts it: the
changelog, the tag `v<version>`, which `cargo generate --tag` takes).

`.github/workflows/template-smoke-test.yml` does the real end-to-end check, weekly, on pushes to
`main` and on every pull request: render-check; every kind × licence × email answer through the real
cargo-generate (manifests, licence files, dprint); and for each kind, in the generated flake's dev
shell, the lock written, the hooks refusing what CI would, `just checks` with the flake's checks
built, `just format` changing nothing, the changelog and the build; and for `bin` and `workspace`
(`lib` releases as `bin` does), real releases against a bare remote, each tag then read as
`publish.yml` reads it.

## Verification status

The template is driven end to end with the real tools, not reasoned about. With **cargo-generate
0.25.0**, **uv 0.11.21** and the dev group's pins (ruff 0.15.14, basedpyright 1.39.3, ty 0.0.38,
pytest 9.0.3, coverage 7.14.1, vulture 2.14), **cocogitto 7.0.0**, **git-cliff 2.13.1**, **pip-audit
2.10.0** and **dprint 0.61.0** (markdown 0.26.0, TOML 0.9.0; nixpkgs' 0.54.0, the dev shell's,
passes them too), all 108 answer combinations -- kind × licence × floor × email (none, or a long
name and address) × keywords (none, or ten) -- generate and, after `uv lock` and their first commit,
pass `just --fmt --check`, `lock-check`, `ruff-checks`, `static`, `vulture`, `pytest` (100%),
`dprint-check`, `cog`, `audit`, `build` and `changelog`; each wheel's and sdist's metadata matches
its manifest; and each flake evaluates on all three systems.

Also confirmed by running it:

- **Releases** against a bare remote, each after a push (`just release` runs no tests and refuses an
  unpushed `main`): a single package's first release tags `v0.1.0` (the declared version) and writes
  the changelog; a second, after a `fix!`, bumps to `v0.2.0` -- pyproject.toml and uv.lock -- with
  the breaking change first and a compare link; an empty third is refused. A workspace releases
  `<name>-core` (`v0.1.0`, then `v0.2.0` after a breaking change) and `<name>` on their own, each
  changelog from its folder's commits alone; a release naming no package, or one that is not a
  member, is refused; so is the command released before the library is on the index (a local one,
  `RELEASE_INDEX_URL`), with a floor below the library's release, or with the library's `src`
  changed since its tag. With a third member under the library, the chain is held: a change to it, a
  floor on it gone stale or the library's requirement changed, each refused; its readme alone not;
  and `tests/test_workspace.py` fails until the root's settings name it. Each tag, at its own
  commit, is read back by `.github/package-tag.sh` (package, folder, version -- a dev version's too)
  and `.github/release-notes.sh`, which refuse a version the package does not declare or the
  changelog does not head. A push refused after the release commit names the commands that finish
  it.
- **The built distributions**: PEP 639 metadata (`License-Expression`, `License-File`), the
  licence texts, `py.typed`, the entry point, the member's requirement on the core.
- **The git hooks**: an unformatted file, a message cog rejects and a pushed revert refused;
  a clean commit and push accepted.
- **The flake of every combination** evaluates on all three systems (`nix flake check --no-build
  --all-systems`, Nix 2.34.6, the shipped flake.lock's nixpkgs) and is nixfmt-clean; its `pins`
  check finds no stale pin, and finds a mutated one. The workspace's command package takes the
  core's derivation as its dependency; the dev shell's Python is the floor. Every package is a
  Python module (a Python environment takes a bin's library; the command is the same derivation),
  and each wheel's source holds the readme and the files license-files names -- a renamed
  `LICENSE` reached hatchling's wheel only once it was read from there.
- **The image prompt**: all 180 combinations with it (`bin` and `workspace` with the image or
  without) pass dprint, nixfmt, actionlint and shellcheck and evaluate on all three systems;
  the image, its check and its workflow exist exactly where chosen, on Linux alone, and five
  of them, one per kind and choice, pass the full list above too.
- **Docker Hub**: image.yml's push and multi-architecture steps, run against a recording
  `docker`, make with no Docker Hub settings the very calls they made before it; with both, each
  architecture pushed to both registries and each index made from its own; with one alone, a name
  Docker would refuse, or a dotted repository name, they stop after GHCR's login, before any push.
- **The name hook** refuses `3d-tool`, `async`, `calendar` and `Über-tool`, and is not copied.
- **The types on every Python**: basedpyright and ty pass the starter code at 3.12, 3.13 and 3.14
  (`--pythonversion`, as CI and the flake run them); the flake's test environment holds the dev
  group's packages.
- **render-check** catches each of seven planted defects: a member's requires-python drifted, a
  misspelled variable, a member's code drifted, a classifier dropped, a placeholder in an
  excluded file, a glob in `ignore`, a wrong `.python-versions`.
- **The shell**: for each kind, with the image or without, the generated project's
  `just shell-check` passes -- with nixos-unstable's shfmt 3.14.1 and just 1.58.0, and with the
  shipped lock's nixos-26.05 shfmt 3.13.1 and just 1.51.0 -- as does its formatter, run as treefmt
  2.6.0 with the same settings and `--ci`, and the flake's `shell` check, run as its derivation runs
  it in a namespace without `/usr/bin/env`; each flake evaluates with its new `format` and `shell`
  checks (against nixos-unstable: nixos-26.05's source is out of this environment's reach).
  Reformatting the recipes changed their layout alone: shfmt's minified output of each is
  unchanged.
- **This repository's tooling**: render-check's copies catch each planted drift; `just
  shell-check`, `just template-shell-check`, actionlint and dprint pass; this flake evaluates on
  all three systems.
- The workflows pass actionlint 1.7.12 with shellcheck 0.11.0.
- **`just format`**, here and in each kind generated (its lock written), with `nix fmt` emulated
  (its formatter's settings, evaluated, run by treefmt 2.6.0): it changes nothing on what generation
  wrote, and, in a bin project, puts back each planted drift -- imports out of order, code ruff
  would reformat, a justfile recipe line, a script recipe shfmt would reformat (`just shell-check`'s
  verdict), Markdown, the Nix. `nix fmt -- --ci` fails on a misindented recipe line, here in either
  justfile and in a generated project's.
- **actionlint in the generated projects**: `just actionlint` and the pre-commit hook pass in each
  kind, and the hook refuses a workflow with an unquoted variable in a `run:` script; the flake's
  new `workflows` check, run as its derivation runs it (a copy in a repository of its own, no
  `/usr/bin/env`), passes for each.

What this does **not** cover -- the smoke-test workflow is what does:

- **Builds under Nix.** The flake's derivations were evaluated, never built: this environment
  reaches no binary cache. So the flake's tests, types and lint, the command check and the
  image have not run; the smoke test builds the image, runs it in Docker and reads its user and
  labels.
- **GitHub Actions itself**, PyPI's Trusted Publishing, the GitHub release and the GHCR push:
  linted, not run.

## Attribution

The workflows, the justfile, `cliff.toml`, `cog.toml`, the hooks and the community documents are
adapted from the [rust-template](https://github.com/veralvx/rust-template) and from
[ffsuite](https://github.com/veramachine/ffsuite), which took them from
[`veralvx/imi`](https://github.com/veralvx/imi) (MIT OR Apache-2.0).

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
  <http://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or <http://opensource.org/licenses/MIT>)

at your option.
