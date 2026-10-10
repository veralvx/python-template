#!/usr/bin/env bash
# A release tag read as the package it releases, its changelog's folder, its version and whether
# it is the main package (true or false): `v0.2.0` is a single package's (the root's, the main
# one), `name-v0.2.0` a workspace member's (packages/name; the main one if its pyproject.toml says
# `[tool.<name>] main = true`). Refused unless the tag's version is the one the package's
# pyproject.toml declares. The version is what follows the prefix: it may hold a `v`
# (0.1.0.dev1), never `-v`. publish.yml's and image.yml's; python3 3.11+ (tomllib).
set -euo pipefail

tag=${1:?usage: package-tag.sh TAG (v0.2.0, or name-v0.2.0 in a workspace)}
if grep -q '^\[project\]' pyproject.toml; then
  [[ $tag == v[0-9]* ]] || { echo "$tag: a single package's tag is v<version>" >&2; exit 1; }
  version=${tag#v}
  package=$(uv version | cut -d ' ' -f 1)
  folder=.
  declared=$(uv version --short)
  main=true
else
  [[ $tag == ?*-v[0-9]* ]] || { echo "$tag: a workspace member's tag is <name>-v<version>" >&2; exit 1; }
  version=${tag##*-v}
  package=${tag%-v*}
  folder=packages/$package
  [[ -f $folder/pyproject.toml ]] || { echo "$tag: no workspace member $package ($folder)" >&2; exit 1; }
  declared=$(uv version --package "$package" --short)
  main=$(python3 - "$folder/pyproject.toml" <<'EOF'
import sys
import tomllib

with open(sys.argv[1], "rb") as file:
    manifest = tomllib.load(file)
own = manifest.get("tool", {}).get(manifest["project"]["name"], {})
print("true" if own.get("main") is True else "false")
EOF
  )
fi
if [[ $version != "$declared" ]]; then
  echo "$tag: $package's pyproject.toml declares $declared" >&2
  exit 1
fi
echo "$package $folder $version $main"
