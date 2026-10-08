# `nix develop`: uv on nixpkgs' Python -- the oldest .python-versions lists, uv's own downloads
# off; `uv sync --locked` installs the dev group, pinned to this nixpkgs' versions -- and the
# other tools the checks and the workflows run. On NixOS, the wheels' executables (ruff, ty,
# basedpyright's node) ask for a standard dynamic loader: programs.nix-ld.enable.
{ pkgs }:
let
  inherit (import ./pythons.nix { inherit pkgs; }) oldest;
  python = oldest.python;
in
pkgs.mkShell {
  packages = [
    python
    pkgs.uv
    pkgs.just
    pkgs.dprint
    pkgs.cocogitto
    pkgs.nixfmt
    pkgs.shellcheck
  ];
  env = {
    UV_PYTHON = "${python}/bin/python";
    UV_PYTHON_DOWNLOADS = "never";
  };
}
