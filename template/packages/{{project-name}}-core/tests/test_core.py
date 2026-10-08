import pytest

from {{crate_name}}_core import greeting


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("Ada", "Hello, Ada!"),
        ("  Ada \n", "Hello, Ada!"),
        ("", "Hello, world!"),
        ("   ", "Hello, world!"),
    ],
)
def test_greeting(name: str, expected: str) -> None:
    assert greeting(name) == expected
