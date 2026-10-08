"""``python -m {{crate_name}}``: the command line."""

# run, never imported: no `if __name__ == "__main__"` test, whose other branch nothing takes
from {{crate_name}}.cli import main

raise SystemExit(main())
