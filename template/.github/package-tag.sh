#!/usr/bin/env bash
# A release tag read as the package it releases, its changelog's folder after it: `v0.2.0` is a
# single package's (the root's), `name-v0.2.0` a workspace member's (packages/name). Refused
# unless the tag's version is the one the package's pyproject.toml declares. release.yml's and
# publish.yml's.
set -euo pipefail

tag=${1:?usage: package-tag.sh TAG (v0.2.0, or name-v0.2.0 in a workspace)}
version=${tag##*v}
if grep -q '^\[project\]' pyproject.toml; then
  [[ $tag == "v$version" ]] || { echo "$tag: a single package's tag is v<version>" >&2; exit 1; }
  package=$(uv version | cut -d ' ' -f 1)
  folder=.
  declared=$(uv version --short)
else
  package=${tag%-v*}
  folder=packages/$package
  [[ -f $folder/pyproject.toml ]] || { echo "$tag: no workspace member $package ($folder)" >&2; exit 1; }
  declared=$(uv version --package "$package" --short)
fi
if [[ $version != "$declared" ]]; then
  echo "$tag: $package's pyproject.toml declares $declared" >&2
  exit 1
fi
echo "$package $folder"
