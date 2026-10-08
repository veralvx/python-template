# The flake's checks. On each Python .python-versions lists: the tests (pytest over the built
# packages, as installed), the types (basedpyright); once, interpreter-free: ruff, nixfmt,
# shellcheck, dead code; the dependency groups' pins held to this nixpkgs; and the command, run
# through its wrapper alone. Nothing project-specific: read from the pyproject files.
{ pkgs }:
let
  inherit (pkgs) lib;

  # what the Python checks read: the repository less its tooling and its prose, so an edit there
  # rebuilds none of them (lint reads its own list)
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
  # lint's: everything it reads, the hooks and the workflows' script among them
  lintSource = lib.fileset.toSource {
    root = ../.;
    fileset = ../.;
  };

  pythons = import ./pythons.nix { inherit pkgs; };

  onPython =
    version:
    let
      python3Packages = pythons.packagesFor version;
      built = import ./packages.nix { inherit pkgs python3Packages; };
      suffix = "py${lib.replaceStrings [ "." ] [ "" ] version}";
      # the packages, installed, with the dev group's test tools (the `pins` keep them the same)
      environment = python3Packages.python.withPackages (
        ps:
        lib.attrValues built.packages
        ++ [
          ps.packaging
          ps.pytest
          ps.pytest-cov
          ps.pytest-timeout
          ps.pytest-xdist
        ]
      );
    in
    {
      # from a writable copy: coverage writes there; no .pytest_cache, nothing kept between builds
      "tests-${suffix}" = pkgs.runCommand "tests-${suffix}" { nativeBuildInputs = [ environment ]; } ''
        cp -r ${source} "$TMPDIR/workspace"
        chmod -R u+w "$TMPDIR/workspace"
        cd "$TMPDIR/workspace"
        python -m pytest -p no:cacheprovider --cov -n auto
        touch $out
      '';
      "types-${suffix}" =
        pkgs.runCommand "types-${suffix}" { nativeBuildInputs = [ pkgs.basedpyright ]; }
          ''
            export HOME=$TMPDIR
            cd ${source}
            basedpyright --pythonpath ${environment}/bin/python
            touch $out
          '';
    };

  # every pin in pyproject.toml's dependency groups, and uv's required version, is this nixpkgs'
  # version: each from python3Packages, but nixpkgs' applications
  pins =
    let
      manifest = lib.importTOML ../pyproject.toml;
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
      nixpkgsVersion = name: (applications.${name} or pkgs.python3Packages.${name}).version;
      pin =
        spec:
        let
          parts = lib.splitString "==" spec;
        in
        lib.throwIfNot (lib.length parts == 2) "pyproject.toml: ${spec} is no name==version" {
          name = lib.head parts;
          version = lib.last parts;
        };
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

  lint =
    pkgs.runCommand "lint"
      {
        nativeBuildInputs = [
          pkgs.ruff
          pkgs.nixfmt
          pkgs.shellcheck
        ];
      }
      ''
        cd ${lintSource}
        ruff check --no-cache .
        ruff format --check --no-cache .
        nixfmt --check flake.nix nix/*.nix
        shellcheck .githooks/* .github/*.sh
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
