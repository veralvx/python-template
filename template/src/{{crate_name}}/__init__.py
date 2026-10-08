"""The ``{{project-name}}`` package."""

__all__ = ["greeting"]


def greeting(name: str) -> str:
    """A greeting for ``name``, its surrounding whitespace stripped; nobody named, the world.

    Args:
        name: Who to greet.

    Returns:
        The greeting, a sentence.
    """
    who = name.strip() or "world"
    return f"Hello, {who}!"
