{
  description = "{{description}}";

  # a release channel: its tools move at a release, with the dependency groups' pins
  # (nix/checks.nix's `pins`); `nix flake update` within it, then `just checks`
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      # Linux on both architectures, and Apple silicon: nixpkgs' Intel macOS support ends with
      # 26.05 (its release notes)
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          built = import ./nix/packages.nix { inherit pkgs; };
        in
        built.packages // { inherit (built) default; }
      );

      # `nix run`: the command, where the project has one
      apps = lib.mapAttrs (
        _: packages:
        lib.optionalAttrs (packages.default.meta ? mainProgram) {
          default = {
            type = "app";
            program = lib.getExe packages.default;
            meta.description = packages.default.meta.description;
          };
        }
      ) self.packages;

      checks = forAllSystems (pkgs: import ./nix/checks.nix { inherit pkgs; });

      devShells = forAllSystems (pkgs: {
        default = import ./nix/shell.nix { inherit pkgs; };
      });

      # `nix fmt`: nixfmt over the tree
      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
