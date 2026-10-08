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
        built.packages
        // {
          inherit (built) default;
        }
{%- if project_kind != "lib" and container_image %}
        # the command's OCI image (nix/image.nix): Linux's alone
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          image = import ./nix/image.nix {
            inherit pkgs;
            package = built.default;
          };
        }
{%- endif %}
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
{% if project_kind != "lib" and container_image %}
      # the image built is checked too -- its layers from the command's closure, which the
      # stream alone would not run -- at the cost of its gzipped copy in the store
      checks = forAllSystems (
        pkgs:
        import ./nix/checks.nix { inherit pkgs; }
        // lib.optionalAttrs (self.packages.${pkgs.stdenv.hostPlatform.system} ? image) {
          inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) image;
        }
      );
{%- else %}
      checks = forAllSystems (pkgs: import ./nix/checks.nix { inherit pkgs; });
{%- endif %}

      devShells = forAllSystems (pkgs: {
        default = import ./nix/shell.nix { inherit pkgs; };
      });

      # `nix fmt`: nixfmt over the tree
      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
