# The command as an OCI image, for Linux: dockerTools' layered image of its package's closure,
# nothing else -- no base image, no /bin/sh (its wrapper's bash is in the closure, by store
# path). `nix build .#image` gives the gzipped docker-archive;
# `.#image.stream`, the script that streams it uncompressed (image.yml's: no second copy of the
# closure in the store). Nothing project-specific: read from the package.
{ pkgs, package }:
let
  inherit (pkgs) lib;
in
pkgs.dockerTools.buildLayeredImage {
  name = package.meta.mainProgram;
  tag = package.version;
  # tempfile's default directory; the image has no other
  extraCommands = "mkdir -m 1777 tmp";
  config = {
    Entrypoint = [ (lib.getExe package) ];
    # nobody: nothing in it needs root, and a numeric user needs no /etc/passwd
    User = "65534:65534";
    # what GHCR reads (docs.github.com, "Working with the Container registry"): the source links
    # the image to its repository
    Labels = {
      "org.opencontainers.image.title" = package.meta.mainProgram;
      "org.opencontainers.image.description" = package.meta.description;
      "org.opencontainers.image.version" = package.version;
      "org.opencontainers.image.source" = package.repository;
      "org.opencontainers.image.licenses" = package.spdxLicense;
    };
  };
}
