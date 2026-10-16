#!/usr/bin/env python3
"""Render the template with Liquid and check the result, without cargo-generate.

A fast local gate for template authors. It answers the questions that only surface *after*
generation otherwise:

  * does every templated file still parse (TOML / YAML / JSON / Nix) once the placeholders are
    substituted, for every combination of prompts?
  * did any placeholder survive into the output unexpanded, or name an undeclared variable?
    (cargo-generate renders a file it cannot render as it stands, and an unknown variable as an
    empty string -- both silently)
  * did a file that must NOT be templated (a workflow, cliff.toml, the justfile, the Nix files)
    hold one of our placeholders?
  * do the placeholder regexes accept their own defaults, and name `ignore` paths that exist?
  * do the copies agree -- the workspace members' code, manifests and licence texts against the
    single package's?
  * does each manifest describe its layout: the Pythons, the licence files, the kind?
  * are this repository's copies of the template's files still the template's (AGENTS.md, Copies
    stay copies): the files, the justfiles' shell recipes, dprint's plugins?

An approximation: cargo-generate uses the Rust `liquid` crate, this python-liquid. They agree on
the subset used here (assign, if/elsif/else, for, split, strip, remove, date, downcase), which is
why the template stays inside it. One known divergence: after a `-%}` trim tag, python-liquid
also drops a file's final newline where liquid-rust keeps it -- so whitespace is the smoke
test's to check, not this.

Usage:  python3 tools/render-check.py   (python-liquid and PyYAML; nix-instantiate if on PATH)
Exit:   0 = all good, 1 = at least one check failed.
"""

from __future__ import annotations

import fnmatch
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tomllib

try:
    from liquid import Environment
except ImportError:  # pragma: no cover - dependency hint
    sys.exit("python-liquid is required:  pip install python-liquid")

try:
    import yaml
except ImportError:  # pragma: no cover - dependency hint
    sys.exit("PyYAML is required:  pip install pyyaml")

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "template"
CONFIG = TEMPLATE / "cargo-generate.toml"
SINGLE = TEMPLATE / "src" / "{{crate_name}}"
CLI = TEMPLATE / "packages" / "{{project-name}}"
CORE = TEMPLATE / "packages" / "{{project-name}}-core"

# cargo-generate's built-ins, plus one sample answer per prompt; `CASES` varies the rest.
BASE_VARS = {
    "project-name": "sample-app",
    "crate_name": "sample_app",
    "authors": "Jane Doe <jane@example.com>",
    "username": "jane",
    "os-arch": "linux-x86_64",
    "within_cargo_project": False,
    "is_init": False,
    "description": "A sample package.",
    "author_name": "Jane Doe",
    "author_email": "jane@example.com",
    "github_username": "jane",
    "keywords": "cli, sample",
}
PYTHONS = ("3.12", "3.13", "3.14")

# A lib is never asked container_image (a conditional placeholder): undefined, as there -- or
# given anyway on the command line (`-d`), which cargo-generate passes through unasked
IMAGES = {"bin": (True, False), "lib": (None, True), "workspace": (True, False)}
CASES = [
    {"project_kind": kind, "license": lic, "python_min": py, **extra}
    | ({} if image is None else {"container_image": image})
    for kind in ("bin", "lib", "workspace")
    for image in IMAGES[kind]
    for lic in ("MIT OR Apache-2.0", "MIT", "Apache-2.0")
    for py in PYTHONS
    for extra in ({}, {"author_email": "", "keywords": ""})
]


def holds(expr: str, vars_: dict[str, object]) -> bool:
    """A conditional's Rhai expression -- comparisons, `&&`, `||`, `!` -- over the answers."""
    python = expr.replace("&&", " and ").replace("||", " or ")
    python = re.sub(r"!(?!=)", " not ", python)
    names = {k.replace("-", "_"): v for k, v in vars_.items()}
    return bool(eval(python, {"__builtins__": {}}, names))  # noqa: S307 - our own config's

# `{{project-name}}` is valid for the Rust liquid crate but the dash parses as subtraction in
# python-liquid, so rewrite the identifier inside tags only -- never in prose that mentions it.
TAG = re.compile(r"\{\{.*?\}\}|\{%.*?%\}", re.DOTALL)


def normalise(text: str) -> str:
    return TAG.sub(lambda m: m.group(0).replace("project-name", "project_name"), text)


# The template's files this repository keeps a copy of, byte for byte (and mode): not rendered here,
# so each original must render to itself
COPIES = (
    "cog.toml",
    "cliff.toml",
    ".editorconfig",
    ".github/release-notes.sh",
    ".githooks/commit-msg",
    ".githooks/pre-push",
    ".github/workflows/style-check-dprint.yml",
    ".github/workflows/style-check-cocogitto.yml",
    ".github/workflows/dependabot-automerge.yml",
)
# the justfile recipes both justfiles hold, the same
COPIED_RECIPES = ("shell-check", "shfmt", "shfmt-recipes")


def recipe(justfile: pathlib.Path, name: str) -> str | None:
    """A recipe's text: its comments and attributes, its line, its body (blank lines included, to
    the next line at the margin)."""
    lines = justfile.read_text().splitlines()
    for i, line in enumerate(lines):
        if re.match(rf"@?{re.escape(name)}(\s[^:]*)?:(?!=)", line):  # `:=`: an assignment
            start = i
            while start > 0 and lines[start - 1].startswith(("#", "[")):
                start -= 1
            end = i + 1
            while end < len(lines) and (not lines[end] or lines[end][0].isspace()):
                end += 1
            while end > i + 1 and not lines[end - 1].strip():
                end -= 1
            return "\n".join(lines[start:end])
    return None


def matches_any(rel: str, globs: list[str]) -> bool:
    return any(
        fnmatch.fnmatch(rel, g) or rel == g or rel.startswith(g.rstrip("/") + "/") for g in globs
    )


def main() -> int:  # noqa: C901, PLR0912, PLR0915 - one gate, read top to bottom
    cfg = tomllib.loads(CONFIG.read_text())
    excluded = cfg["template"].get("exclude", [])
    conditionals = cfg.get("conditional", {})
    # the prompts, those asked under a condition among them
    placeholders = cfg["placeholders"] | {
        name: spec for section in conditionals.values() for name, spec in section.get("placeholders", {}).items()
    }
    env = Environment()
    failures: list[str] = []

    def fail(msg: str) -> None:
        failures.append(msg)
        print(f"  FAIL {msg}")

    def render(path: pathlib.Path, vars_: dict[str, object]) -> str:
        return env.from_string(normalise(path.read_text())).render(**vars_)

    print("== placeholder defaults vs regexes")
    for name, spec in placeholders.items():
        if "regex" in spec and "default" in spec and not re.search(spec["regex"], str(spec["default"])):
            fail(f"{name}: default {spec['default']!r} rejected by its own regex")
        if "choices" in spec and "default" in spec and spec["default"] not in spec["choices"]:
            fail(f"{name}: default {spec['default']!r} is not one of its choices")
    if tuple(placeholders["python_min"]["choices"]) != PYTHONS:
        fail(f"python_min's choices are not {PYTHONS}: update this harness and .python-versions")
    print(f"  checked {len(placeholders)} placeholders")

    # `ignore` entries are literal paths, not globs: a glob would name no path and be skipped
    # silently, shipping a file meant to be dropped
    print("== conditional ignore paths")
    for expr, section in conditionals.items():
        for entry in section.get("ignore", []):
            if any(ch in entry for ch in "*?["):
                fail(f"{expr}: ignore entry {entry!r} looks like a glob; ignore takes literal paths")
            elif not (TEMPLATE / entry).exists():
                fail(f"{expr}: ignore entry {entry!r} does not exist in the template")
    print(f"  checked {sum(len(s.get('ignore', [])) for s in conditionals.values())} paths")

    # The single package and the workspace hold the same code twice: the library (__init__),
    # the command line, `python -m`, and their tests. Only the import of the library differs.
    print("== duplicated code")
    pairs = [
        (SINGLE / "cli.py", CLI / "src" / "{{crate_name}}" / "cli.py"),
        (SINGLE / "__main__.py", CLI / "src" / "{{crate_name}}" / "__main__.py"),
        (TEMPLATE / "tests" / "test_cli.py", CLI / "tests" / "test_cli.py"),
        (TEMPLATE / "tests" / "test_{{crate_name}}.py", CORE / "tests" / "test_core.py"),
    ]
    for single, member in pairs:
        if single.read_text().replace("{{crate_name}} import", "{{crate_name}}_core import") != (
            member.read_text()
        ) and single.read_text() != member.read_text():
            fail(f"{member.relative_to(TEMPLATE)} has drifted from {single.relative_to(TEMPLATE)}")

    def body(path: pathlib.Path) -> str:  # the code, its module docstring aside
        return path.read_text().split('"""', 2)[2]

    if body(SINGLE / "__init__.py") != body(CORE / "src" / "{{crate_name}}_core" / "__init__.py"):
        fail("the core's __init__.py has drifted from the single package's")
    print(f"  compared {len(pairs) + 1} pairs")

    # Each member carries copies of the root's licence texts (its sdist holds its own folder)
    print("== member licence copies")
    for member in (CLI, CORE):
        for name in ("LICENSE-MIT", "LICENSE-APACHE"):
            copy = member / name
            if not copy.exists():
                fail(f"{copy.relative_to(TEMPLATE)} is missing")
            elif copy.read_bytes() != (TEMPLATE / name).read_bytes():
                fail(f"{copy.relative_to(TEMPLATE)} differs from the root's {name}")
    print("  checked the members' licence files")

    # This repository's copies are the template's: the files (an original holding Liquid would
    # render to something else), the shell recipes, dprint's plugins.
    print("== copies of the template's files")
    for rel in COPIES:
        original, copy = TEMPLATE / rel, ROOT / rel
        if not copy.is_file() or not original.is_file():
            fail(f"{rel}: missing, here or in template/")
            continue
        if copy.read_bytes() != original.read_bytes():
            fail(f"{rel} differs from template/{rel}: change the original, then copy it")
        if os.access(copy, os.X_OK) != os.access(original, os.X_OK):
            fail(f"{rel}: executable here or in template/, not both")
        if not matches_any(rel, excluded) and TAG.search(original.read_text()):
            fail(f"template/{rel} holds Liquid: its copy here would not be what it renders to")
    for name in COPIED_RECIPES:
        mine, theirs = recipe(ROOT / "justfile", name), recipe(TEMPLATE / "justfile", name)
        if mine is None or theirs is None:
            fail(f"justfile recipe {name}: missing, here or in template/")
        elif mine != theirs:
            fail(f"justfile recipe {name} differs from template/justfile's")
    plugins = []
    for d in (ROOT, TEMPLATE):
        # JSONC: a whole-line comment dropped; one after a value is left to fail here
        try:
            text = re.sub(r"(?m)^\s*//.*$", "", (d / "dprint.json").read_text())
            plugins.append(json.loads(text)["plugins"])
        except (json.JSONDecodeError, KeyError) as error:
            fail(f"{d / 'dprint.json'}: no plugins read ({error!r})")
    if len(plugins) == 2 and plugins[0] != plugins[1]:
        fail("dprint.json's plugins are not template/dprint.json's")
    print(f"  checked {len(COPIES)} files, {len(COPIED_RECIPES)} recipes, the plugins")

    nix = shutil.which("nix-instantiate")
    # the output's files: cargo-generate copies neither its config nor its hook scripts
    hooks = {name for names in cfg.get("hooks", {}).values() for name in names}
    for name in sorted(hooks):
        if not (TEMPLATE / name).is_file():
            fail(f"hook {name} does not exist")
    skipped = {"cargo-generate.toml"} | hooks
    files = sorted(
        p for p in TEMPLATE.rglob("*") if p.is_file() and str(p.relative_to(TEMPLATE)) not in skipped
    )

    # Every variable referenced in a templated file must be declared or built in: cargo-generate
    # renders an unknown one as an empty string, which no "leftover {{" check can see
    print("== variable references")
    builtins = {"project-name", "crate_name", "crate_type", "authors", "username", "os-arch", "within_cargo_project", "is_init"}  # fmt: skip
    known = builtins | set(placeholders)
    ident = re.compile(r"[A-Za-z_][A-Za-z0-9_-]*")
    literal = re.compile(r"\"[^\"]*\"|'[^']*'")
    reserved = {
        "if", "elsif", "else", "endif", "unless", "endunless", "for", "endfor", "in", "assign",
        "and", "or", "contains", "true", "false", "nil", "empty", "forloop", "last", "first",
        "now", "strip", "split", "replace", "remove", "date", "raw", "endraw", "downcase",
    }  # fmt: skip
    refs = 0
    for path in files:
        rel = str(path.relative_to(TEMPLATE))
        if matches_any(rel, excluded):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        local = set(re.findall(r"assign\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text))
        local |= set(re.findall(r"for\s+([A-Za-z_][A-Za-z0-9_]*)\s+in", text))
        for match in TAG.finditer(text):
            for token in ident.findall(literal.sub("", match.group(0).strip("{}%- "))):
                refs += 1
                if token not in reserved | known | local:
                    fail(f"{rel}: unknown variable {token!r} -- it would render as an empty string")
    print(f"  checked {refs} identifier references")

    # Excluded files are copied verbatim: a placeholder there would ship unexpanded
    print("== exclude list integrity")
    ours = set(placeholders) | {"project-name", "crate_name"}
    verbatim = [p for p in files if matches_any(str(p.relative_to(TEMPLATE)), excluded)]
    for path in verbatim:
        text = path.read_text(encoding="utf-8", errors="replace")
        for var in ours:
            if re.search(r"\{\{\s*" + re.escape(var) + r"\s*\}\}", text):
                fail(f"{path.relative_to(TEMPLATE)} is on the exclude list but contains {{{{{var}}}}}")
    print(f"  checked {len(verbatim)} excluded files")

    for case in CASES:
        vars_ = {**BASE_VARS, **case}
        vars_["project_name"] = vars_["project-name"]
        image = case.get("container_image") is True and case["project_kind"] != "lib"
        label = f"{case['project_kind']}/{case['license']}/{case['python_min']}" + (
            "/bare" if case.get("author_email") == "" else ""
        ) + {None: "", True: "/image", False: "/no-image"}[case.get("container_image")]
        ignored: list[str] = []
        for expr, section in conditionals.items():
            try:
                if holds(expr, vars_):
                    ignored.extend(section.get("ignore", []))
            except Exception as exc:  # noqa: BLE001 - report and continue
                fail(f"harness cannot evaluate conditional {expr!r}: {exc}")

        rendered = 0
        outputs: dict[str, str] = {}
        for path in files:
            rel = str(path.relative_to(TEMPLATE))
            # NOT skipping `ignored` files, though cargo-generate removes them before rendering:
            # every case renders every file, so every file's Liquid is checked in every case
            raw = path.read_text(encoding="utf-8", errors="replace")
            if matches_any(rel, excluded):
                out = raw
            else:
                try:
                    out = env.from_string(normalise(raw)).render(**vars_)
                except Exception as exc:  # noqa: BLE001 - report and continue
                    fail(f"{label}: {rel}: liquid error: {exc}")
                    continue
                if leftovers := TAG.findall(out):
                    fail(f"{label}: {rel}: unexpanded template syntax: {leftovers[:3]}")
                rendered += 1
            outputs[rel] = out
            try:
                if path.suffix == ".toml":
                    tomllib.loads(out)
                elif path.suffix in (".yml", ".yaml"):
                    yaml.safe_load(out)
                elif path.suffix == ".json" and path.name != "dprint.json":  # JSONC: comments
                    json.loads(out)
                elif path.suffix == ".nix" and nix and rel not in ignored:
                    parsed = subprocess.run(  # noqa: S603 - nix-instantiate, from PATH
                        [nix, "--parse", "-"], input=out, capture_output=True, text=True, check=False
                    )
                    if parsed.returncode != 0:
                        raise ValueError(parsed.stderr.strip())  # noqa: TRY301
            except Exception as exc:  # noqa: BLE001 - report and continue
                fail(f"{label}: {rel}: invalid {path.suffix.lstrip('.') or 'text'} after render: {exc}")

        # The manifests describe the layout: the Pythons, the licence files, the kind
        kind = case["project_kind"]
        pythons = [v for v in PYTHONS if v >= case["python_min"]]
        if render(TEMPLATE / ".python-versions", vars_).split() != pythons:
            fail(f"{label}: .python-versions is not {pythons}")
        root = tomllib.loads(render(TEMPLATE / "pyproject.toml", vars_))
        tools = root["tool"]
        if tools["ruff"]["target-version"] != "py" + case["python_min"].replace(".", ""):
            fail(f"{label}: ruff's target-version is not the floor")
        if tools["basedpyright"]["pythonVersion"] != case["python_min"]:
            fail(f"{label}: basedpyright's pythonVersion is not the floor")
        licences = [f"LICENSE-{n}" for n in ("MIT", "APACHE") if n.lower()[:3] in case["license"].lower()]
        manifests = (
            [tomllib.loads(render(member / "pyproject.toml", vars_)) for member in (CLI, CORE)]
            if kind == "workspace"
            else [root]
        )
        if (kind == "workspace") == ("project" in root):
            fail(f"{label}: the root's [project] table does not match project_kind")
        if (kind == "workspace") != ("workspace" in tools.get("uv", {})):
            fail(f"{label}: [tool.uv.workspace] does not match project_kind")
        for manifest in manifests:
            project = manifest["project"]
            name = project["name"]
            if project["license"] != case["license"] or project["license-files"] != licences:
                fail(f"{label}: {name}: licence {project['license']!r}, files {project['license-files']}")
            if project["requires-python"] != f">={case['python_min']}":
                fail(f"{label}: {name}: requires-python is not the floor")
            listed = [c.rsplit(" :: ", 1)[1] for c in project["classifiers"] if re.fullmatch(r"Programming Language :: Python :: 3\.\d+", c)]
            if listed != pythons:
                fail(f"{label}: {name}: its Python classifiers are {listed}, not {pythons}")
            author = {"name": "Jane Doe"} | ({"email": vars_["author_email"]} if vars_["author_email"] else {})
            if project["authors"] != [author]:
                fail(f"{label}: {name}: authors is {project['authors']!r}")
            if ("keywords" in project) != bool(vars_["keywords"]):
                fail(f"{label}: {name}: keywords present for an empty answer, or missing")
            scripts = "scripts" in project
            if scripts != (kind == "bin" or name == vars_["project-name"] and kind == "workspace"):
                fail(f"{label}: {name}: [project.scripts] present={scripts}")
        if kind == "workspace":
            # the members' [project] tables are the single package's, but for what tells them apart
            single = tomllib.loads(render(TEMPLATE / "pyproject.toml", {**vars_, "project_kind": "bin"}))["project"]
            own = {"name", "description", "dependencies", "urls", "scripts", "classifiers"}
            for manifest in manifests:
                shared = {k: v for k, v in manifest["project"].items() if k not in own}
                if shared != {k: v for k, v in single.items() if k not in own}:
                    fail(f"{label}: {manifest['project']['name']}'s [project] has drifted from the single package's")
        rendered_files = {str(p.relative_to(TEMPLATE)) for p in files if not matches_any(str(p.relative_to(TEMPLATE)), ignored)}
        if any(f.startswith("packages/") for f in rendered_files) != (kind == "workspace"):
            fail(f"{label}: packages/ kept for {kind}")
        if any(f.startswith("src/") for f in rendered_files) == (kind == "workspace"):
            fail(f"{label}: src/ dropped for {kind}")
        # the image: its Nix file, its workflow and the flake's output, all or none
        for name in ("nix/image.nix", ".github/workflows/image.yml", ".github/image-registries.sh"):
            if (name in rendered_files) != image:
                fail(f"{label}: {name} {'missing' if image else 'kept'}")
        if ("nix/image.nix" in outputs["flake.nix"]) != image:
            fail(f"{label}: flake.nix's image output does not match container_image")
        print(f"== render {label}: {rendered} files, manifests checked")

    print()
    if failures:
        print(f"{len(failures)} FAILURE(S)")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
