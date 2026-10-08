# The project's packages, built as nixpkgs builds Python (a wheel by hatchling, installed by
# installer), each from its own pyproject.toml: name, version, description, licence, homepage,
# the Python it needs, its dependencies, its command. Nothing here is project-specific: a single
# package is the root's [project]; a workspace's members are [tool.uv.workspace]'s `members`
# (each a folder, or a `folder/*` glob of them).
#
# A dependency that is a member is that member's package; any other is nixpkgs' Python package
# of its normalised name (python3Packages.<name>) -- one nixpkgs lacks, or names otherwise, fails
# evaluation naming it, to be mapped in `nixpkgsName` below.
{
  pkgs,
  # the oldest Python .python-versions lists: the project's floor
  python3Packages ? (import ./pythons.nix { inherit pkgs; }).oldest,
}:
let
  inherit (pkgs) lib;

  rootManifest = lib.importTOML ../pyproject.toml;
  folders =
    if rootManifest ? project then
      [ ../. ]
    else
      lib.concatMap (
        member:
        let
          glob = builtins.match "(.*)/\\*" member;
          parent = ../. + "/${lib.head glob}";
        in
        if glob == null then
          [ (../. + "/${member}") ]
        else
          lib.mapAttrsToList (name: _: parent + "/${name}") (
            lib.filterAttrs (
              name: type: type == "directory" && builtins.pathExists (parent + "/${name}/pyproject.toml")
            ) (builtins.readDir parent)
          )
      ) rootManifest.tool.uv.workspace.members;

  # PEP 503's normalised name: lowercase, runs of -_. as one hyphen
  normalise =
    name:
    lib.toLower (lib.concatStringsSep "-" (lib.filter lib.isString (builtins.split "[-_.]+" name)));
  # a PEP 508 requirement's name: what precedes its extras, version, marker or URL
  requirementName =
    requirement: normalise (lib.head (builtins.match "[[:space:]]*([A-Za-z0-9._-]+).*" requirement));
  # nixpkgs' attribute for a PyPI name, where the two differ: add entries as they come up
  nixpkgsName = name: { }.${name} or name;

  manifests = map (folder: {
    inherit folder;
    project = (lib.importTOML (folder + "/pyproject.toml")).project;
  }) folders;
  memberNames = map (m: normalise m.project.name) manifests;

  build =
    self:
    { folder, project }:
    let
      # requires-python, a floor alone (">=3.13"): an older interpreter refused at evaluation
      floor = builtins.match ">=([0-9.]+)" project.requires-python;
      oldest = lib.throwIf (floor == null) "${project.name}: requires-python is no floor alone" (
        lib.head floor
      );
      # the SPDX expression's identifiers, its operators and parentheses aside
      licences = lib.subtractLists [ "" "AND" "OR" ] (
        lib.filter lib.isString (builtins.split "[ ()]+" project.license)
      );
      scripts = project.scripts or { };
      dependency =
        requirement:
        let
          name = requirementName requirement;
        in
        if lib.elem name memberNames then
          self.${name}
        else
          python3Packages.${nixpkgsName name}
          or (throw "${project.name}: nixpkgs has no python3Packages.${nixpkgsName name} for ${requirement}");
      builder =
        if scripts == { } then
          python3Packages.buildPythonPackage
        else
          python3Packages.buildPythonApplication;
    in
    builder {
      pname = project.name;
      inherit (project) version;
      # what its wheel takes, and what hatchling reads to build it
      src = lib.fileset.toSource {
        root = folder;
        fileset = lib.fileset.unions [
          (folder + "/pyproject.toml")
          (folder + "/README.md")
          (folder + "/src")
          (lib.fileset.fileFilter (file: lib.hasPrefix "LICENSE-" file.name) folder)
        ];
      };
      disabled = python3Packages.pythonOlder oldest;
      pyproject = true;
      build-system = [ python3Packages.hatchling ];
      dependencies = map dependency (project.dependencies or [ ]);
      doCheck = false; # the tests run once, over every package: nix/checks.nix
      pythonImportsCheck = [ (lib.replaceStrings [ "-" ] [ "_" ] project.name) ];
      meta = {
        inherit (project) description;
        homepage = project.urls.Homepage;
        license = map lib.getLicenseFromSpdxId licences;
      }
      // lib.optionalAttrs (scripts != { }) { mainProgram = lib.head (lib.attrNames scripts); };
    };

  packages = lib.fix (
    self:
    lib.listToAttrs (
      map (m: {
        name = normalise m.project.name;
        value = build self m;
      }) manifests
    )
  );
  # the command when there is one -- a workspace's, its one member with scripts -- else the root
  commands = lib.filter (p: p.meta ? mainProgram) (lib.attrValues packages);
in
{
  inherit packages;
  default =
    if commands != [ ] then
      lib.head commands
    else
      packages.${
        normalise (if rootManifest ? project then rootManifest.project.name else lib.head memberNames)
      };
}
