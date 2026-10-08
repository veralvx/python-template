# The Pythons .python-versions lists, oldest first, as nixpkgs' package sets: the one place the
# Nix files read them (the tests and types run on each; the packages and the shell, the oldest).
{ pkgs }:
let
  inherit (pkgs) lib;
  versions = lib.filter (v: v != "") (lib.splitString "\n" (lib.readFile ../.python-versions));
  # "3.13" -> pkgs.python313Packages
  packagesFor = version: pkgs."python${lib.replaceStrings [ "." ] [ "" ] version}Packages";
in
{
  inherit versions packagesFor;
  oldest = packagesFor (lib.head versions);
}
