"""The workspace as a whole: what no member's own tests can see."""

import tomllib
from pathlib import Path
from typing import cast

import pytest
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

ROOT = Path(__file__).parent.parent


def _manifest(folder: Path) -> dict[str, object]:
    with (folder / "pyproject.toml").open("rb") as manifest:
        return tomllib.load(manifest)


def _project(folder: Path) -> dict[str, object]:
    return cast("dict[str, object]", _manifest(folder)["project"])


def _tool(*keys: str) -> object:
    """A setting of the root's [tool] table, by its keys."""
    value: object = _manifest(ROOT)["tool"]
    for key in keys:
        value = cast("dict[str, object]", value)[key]
    return value


# the members as uv finds them: [tool.uv.workspace]'s globs, each a folder with a pyproject.toml
MEMBERS = sorted(
    path.parent
    for pattern in cast("list[str]", _tool("uv", "workspace", "members"))
    for path in ROOT.glob(f"{pattern}/pyproject.toml")
)
NAMES = [folder.name for folder in MEMBERS]


def _requirements(folder: Path) -> list[Requirement]:
    return [
        Requirement(line) for line in cast("list[str]", _project(folder).get("dependencies", []))
    ]


def _names_and_versions() -> dict[str, str]:
    return {
        canonicalize_name(str(project["name"])): str(project["version"])
        for project in map(_project, MEMBERS)
    }


@pytest.mark.parametrize("member", MEMBERS, ids=NAMES)
def test_a_members_requirement_on_another_admits_its_version(member: Path) -> None:
    # uv resolves a member from the workspace whatever its requirement says; PyPI does not: a
    # range the other member's released version falls outside would install nowhere
    versions = _names_and_versions()
    for requirement in _requirements(member):
        name = canonicalize_name(requirement.name)
        if name in versions:
            assert requirement.specifier.contains(versions[name]), (name, str(requirement))


@pytest.mark.parametrize("member", MEMBERS, ids=NAMES)
def test_a_member_carries_the_roots_licence_texts(member: Path) -> None:
    # a member's sdist holds its folder alone: the licence texts its license-files name, copied
    root = sorted(path.name for path in ROOT.glob("LICENSE-*"))
    assert sorted(path.name for path in member.glob("LICENSE-*")) == root
    for name in root:
        assert (member / name).read_text() == (ROOT / name).read_text()


def test_the_workspace_has_members() -> None:
    assert MEMBERS  # else every test over them is skipped, checking nothing


@pytest.mark.parametrize("member", MEMBERS, ids=NAMES)
def test_the_roots_settings_name_each_member(member: Path) -> None:
    # they list the members by hand: a member added and forgotten in one is linted, typed,
    # tested or measured as no package of this workspace (README.md: a new member)
    def paths(*keys: str) -> set[Path]:
        return {ROOT / entry for entry in cast("list[str]", _tool(*keys))}

    assert member / "src" in paths("ruff", "src")
    assert member / "src" in paths("basedpyright", "extraPaths")
    assert member / "tests" in paths("pytest", "ini_options", "testpaths")
    # its import name, as nix/packages.nix's import check reads it: the name, `-` as `_`
    module = str(_project(member)["name"]).replace("-", "_")
    assert module in cast("list[str]", _tool("coverage", "run", "source"))
