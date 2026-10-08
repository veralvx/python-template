"""The workspace as a whole: what no member's own tests can see."""

import tomllib
from pathlib import Path
from typing import cast

import pytest
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

ROOT = Path(__file__).parent.parent
MEMBERS = sorted(path.parent for path in ROOT.glob("packages/*/pyproject.toml"))
NAMES = [folder.name for folder in MEMBERS]


def _project(folder: Path) -> dict[str, object]:
    with (folder / "pyproject.toml").open("rb") as manifest:
        return cast("dict[str, object]", tomllib.load(manifest)["project"])


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


def test_the_workspace_has_its_members() -> None:
    assert len(MEMBERS) == 2
