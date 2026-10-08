# AGENTS.md

Repository rules for `{{project-name}}`. These apply to every contributor, human or AI-assisted.

## 1. The lint and type policy is the design

`pyproject.toml` turns on **every** ruff rule (`select = ["ALL"]`) and runs basedpyright in its
strictest mode (`typeCheckingMode = "all"`, warnings failing). Both are pinned
(`[dependency-groups]`), so the verdict is the same in `just checks`, CI and the flake.

The opt-outs are few, at the top of `[tool.ruff.lint]`, each with its reason; the tests have
their own, under `per-file-ignores`. The alternative -- choosing rules one at a time -- silently
leaves out every rule written after the list was made.

**Never add a blanket ignore to silence a new rule.** Either fix the site, or add the ignore to
`pyproject.toml` with a comment saying why the rule is wrong for this codebase.

## 2. Types: no `Any`

basedpyright's `all` mode reports every `Any` that reaches your code (`reportAny`,
`reportUnknown*`). Where a library hands one over -- argparse's `Namespace`, a parsed TOML or JSON
document -- give it a type at the boundary:

- `parse_args(argv, namespace=_Arguments())`, with `_Arguments(argparse.Namespace)` declaring
  each attribute's type;
- `cast("list[str]", document.get("dependencies", []))` once the shape is known, and checked
  where it is not.

A call whose result is unused is written `_ = call()` (`reportUnusedCallResult`): the discard is
then visible, not accidental.

## 3. Silence a rule at the site, with a reason

```python
process = subprocess.run(argv, check=False)  # noqa: S603 -- argv is ours, never a shell
value = untyped()  # pyright: ignore[reportAny] -- the library is unannotated
```

Name the rule: a bare `# noqa` or `# type: ignore` is itself an error (`PGH004`,
basedpyright's `reportIgnoreCommentWithoutRule`), and one that stops applying is reported too
(`RUF100`, `reportUnnecessaryTypeIgnoreComment`), so a justification cannot outlive the code it
justified.

A reason that restates the rule ("-- we need a subprocess here") is not a reason. Say what makes
the site safe.

## 4. Commits

[Conventional Commits](https://www.conventionalcommits.org/) are enforced by `cog check` locally
and in CI. The changelog is generated from the commits (`cliff.toml`), so the subject line is
user-facing text; `chore`, `ci` and `style` commits stay out of it, and `!` or a
`BREAKING CHANGE` footer lists a commit first:

```
feat(cli): accept the name from standard input
fix: strip a trailing newline from the name
docs: explain the greeting's fallback
build(deps): require packaging 26
```

The git hooks (`just install-hooks`) check the same before a commit and a push; never bypass them
with `--no-verify`. `git revert` writes `Revert "..."`, which CI refuses: reword it as
`revert: ...`.

## 5. Before you claim a change is done

Run `just checks`. It is what CI runs: the lock, ruff, the types, dead code, the tests with every
line and branch covered, dprint, the commit messages, pip-audit, and the flake's checks -- the
tests again on every supported Python, against the built packages. Reporting "done" on a change
that has not passed it is the one thing that wastes the most time here.

If a check fails for reasons unrelated to your change, say so explicitly rather than working
around it -- a broken check that everyone routes around stops protecting anything.
