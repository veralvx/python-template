# The flake's checks. On each Python .python-versions lists: the tests (pytest over the built
# packages, as installed), the types (basedpyright); once, interpreter-free: ruff, the format
# (`nix fmt`'s verdict: nixfmt, shfmt, just's own), the shell (`just shell-check`), the workflows
# (actionlint), dead code; the dependency groups' pins held to this nixpkgs; and the command, run
# through its wrapper alone. Nothing project-specific: read from the pyproject files.
{ pkgs }:
let
  inherit (pkgs) lib;

  # what the Python checks read: the repository less the tooling and documents below, so an edit
  # there rebuilds none of them (lint reads everything). The flake's source is git's files alone:
  # no .venv or build output reaches either.
  source = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.difference ../. (
      lib.fileset.unions (
        map lib.fileset.maybeMissing [
          ../.github
          ../.githooks
          ../.gitignore
          ../AGENTS.md
          ../CHANGELOG.md
          ../CODE_OF_CONDUCT.md
          ../CONTRIBUTING.md
          ../SECURITY.md
          ../cliff.toml
          ../cog.toml
          ../dprint.json
          ../flake.lock
          ../flake.nix
          ../justfile
          ../nix
        ]
      )
    );
  };
  # lint's, format's, shell's and workflows': the whole repository
  lintSource = lib.fileset.toSource {
    root = ../.;
    fileset = ../.;
  };

  pythons = import ./pythons.nix { inherit pkgs; };

  manifest = lib.importTOML ../pyproject.toml;
  # the tools nixpkgs carries as applications, not as Python packages
  applications = {
    inherit (pkgs)
      basedpyright
      ruff
      ty
      pip-audit
      git-cliff
      uv
      ;
  };
  # a dependency group's `name==version` pins, read
  pin =
    spec:
    let
      parts = lib.splitString "==" spec;
    in
    lib.throwIfNot (lib.length parts == 2) "pyproject.toml: ${spec} is no name==version" {
      name = lib.head parts;
      version = lib.last parts;
    };
  # the dev group's Python packages (pytest, its plugins...), the tests' environment
  testTools = lib.filter (name: !applications ? ${name}) (
    map (spec: (pin spec).name) manifest.dependency-groups.dev
  );

  onPython =
    version:
    let
      python3Packages = pythons.packagesFor version;
      built = import ./packages.nix { inherit pkgs python3Packages; };
      suffix = "py${lib.replaceStrings [ "." ] [ "" ] version}";
      # the packages, installed, with the dev group's Python packages (the `pins` keep them the
      # same)
      environment = python3Packages.python.withPackages (
        ps: lib.attrValues built.packages ++ map (name: ps.${name}) testTools
      );
    in
    {
      # from a writable copy: coverage writes there; no .pytest_cache, nothing kept between builds
      "tests-${suffix}" = pkgs.runCommand "tests-${suffix}" { nativeBuildInputs = [ environment ]; } ''
        cp -r ${source} "$TMPDIR/workspace"
        chmod -R u+w "$TMPDIR/workspace"
        cd "$TMPDIR/workspace"
        # as many workers as the build's cores (nixpkgs' own pytest-xdist hook): not the machine's
        python -m pytest -p no:cacheprovider --cov --numprocesses="$NIX_BUILD_CORES"
        touch $out
      '';
      "types-${suffix}" =
        pkgs.runCommand "types-${suffix}" { nativeBuildInputs = [ pkgs.basedpyright ]; }
          ''
            export HOME=$TMPDIR
            cd ${source}
            basedpyright --pythonpath ${environment}/bin/python --pythonversion ${version}
            touch $out
          '';
    };

  # every pin in pyproject.toml's dependency groups, and uv's required version, is this nixpkgs'
  # version: each from python3Packages, but nixpkgs' applications
  pins =
    let
      nixpkgsVersion = name: (applications.${name} or pkgs.python3Packages.${name}).version;
      uv = {
        name = "uv";
        version = lib.removePrefix "==" manifest.tool.uv.required-version;
      };
      stale = lib.filter (p: nixpkgsVersion p.name != p.version) (
        [ uv ] ++ map pin (lib.concatLists (lib.attrValues manifest.dependency-groups))
      );
    in
    pkgs.runCommand "pins"
      {
        stale = lib.concatMapStringsSep "\n" (
          p: "${p.name}: pinned ${p.version}, nixpkgs ${nixpkgsVersion p.name}"
        ) stale;
      }
      ''
        if [ -n "$stale" ]; then
          printf '%s\n' "$stale" >&2
          exit 1
        fi
        touch $out
      '';

  built = import ./packages.nix { inherit pkgs; };
in
lib.foldl' (checks: version: checks // onPython version) { } pythons.versions
// {
  inherit pins;

  lint = pkgs.runCommand "lint" { nativeBuildInputs = [ pkgs.ruff ]; } ''
    cd ${lintSource}
    ruff check --no-cache .
    ruff format --check --no-cache .
    touch $out
  '';

  # the formatter's verdict on the whole tree: what `nix fmt` would change fails it
  format = (import ./formatter.nix { inherit pkgs; }).check lintSource;

  # `just shell-check` on a copy, in a repository of its own: it lists the scripts git does not
  # ignore. The sandbox has no /usr/bin/env, which the script recipes name: their bash is named
  # by its path instead (to `just shell-check`, the same shell either way).
  shell =
    pkgs.runCommand "shell"
      {
        nativeBuildInputs = [
          pkgs.just
          pkgs.jq
          pkgs.gitMinimal
          pkgs.shellcheck
          pkgs.shfmt
        ];
      }
      ''
        cp -r ${lintSource} "$TMPDIR/project"
        chmod -R u+w "$TMPDIR/project"
        cd "$TMPDIR/project"
        export HOME="$TMPDIR"
        substituteInPlace justfile \
          --replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'
        git init --quiet
        git add --all
        just shell-check
        touch $out
      '';

  # actionlint on a copy, in a repository of its own, as `just actionlint` runs it: with no file
  # named, actionlint finds the workflows, and .github/actionlint.yaml if there is one, from the
  # repository's root
  workflows =
    pkgs.runCommand "workflows"
      {
        nativeBuildInputs = [
          pkgs.actionlint
          pkgs.shellcheck
          pkgs.gitMinimal
        ];
      }
      ''
        cp -r ${lintSource} "$TMPDIR/project"
        chmod -R u+w "$TMPDIR/project"
        cd "$TMPDIR/project"
        export HOME="$TMPDIR"
        git init --quiet
        actionlint
        touch $out
      '';

  vulture = pkgs.runCommand "vulture" { nativeBuildInputs = [ pythons.oldest.vulture ]; } ''
    cd ${source}
    vulture
    touch $out
  '';
}
// lib.optionalAttrs (built.default.meta ? mainProgram) {
  # the command as a user runs it: its wrapper alone gives it its environment (env -i)
  command =
    pkgs.runCommand "command"
      {
        exe = lib.getExe built.default;
        expected = "${built.default.meta.mainProgram} ${built.default.version}";
      }
      ''
        actual=$(env -i "$exe" --version)
        if [ "$actual" != "$expected" ]; then
          echo "--version gave '$actual', expected '$expected'" >&2
          exit 1
        fi
        touch $out
      '';
}
