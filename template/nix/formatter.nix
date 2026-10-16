# `nix fmt` (flake.nix's formatter): each tool on its own files -- the Nix by nixfmt, the shell
# scripts by shfmt (as .editorconfig says), by extension, the hooks by their directory, as they
# have none, the justfile by just, by name, as `just --fmt` takes one. Its `check` is the flake's
# `format` check. The Python is ruff's (`just format`).
{ pkgs }:
pkgs.treefmt.withConfig {
  settings = {
    on-unmatched = "info";
    formatter = {
      nixfmt = {
        command = "nixfmt";
        includes = [ "*.nix" ];
      };
      shfmt = {
        command = "shfmt";
        options = [ "--write" ];
        includes = [
          "*.sh"
          ".githooks/*"
        ];
      };
      just = {
        command = "just";
        options = [
          "--fmt"
          "--unstable"
          "--justfile"
        ];
        includes = [ "justfile" ];
      };
    };
  };
  runtimeInputs = [
    pkgs.nixfmt
    pkgs.shfmt
    pkgs.just
  ];
}
