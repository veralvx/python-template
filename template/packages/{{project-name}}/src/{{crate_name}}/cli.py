"""The ``{{project-name}}`` command line."""

import argparse
import sys
from importlib.metadata import version

from {{crate_name}}_core import greeting

NAME = "{{project-name}}"  # the command's, and its distribution's


class _Arguments(argparse.Namespace):
    """The parsed command line, typed: argparse's own Namespace holds Any."""

    name: str = ""


def main(argv: list[str] | None = None) -> int:
    """Run the command line.

    Args:
        argv: The arguments, the program's name left out (default: the process's).

    Returns:
        The exit status.
    """
    parser = argparse.ArgumentParser(prog=NAME, description="Print a greeting.")
    _ = parser.add_argument("--version", action="version", version=f"%(prog)s {version(NAME)}")
    _ = parser.add_argument("name", nargs="?", default="", help="who to greet (default: the world)")
    arguments = parser.parse_args(argv, namespace=_Arguments())
    _ = sys.stdout.write(greeting(arguments.name) + "\n")
    return 0
