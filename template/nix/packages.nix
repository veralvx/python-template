# The project's packages, built as nixpkgs builds Python (a wheel by hatchling, installed by
# installer), each from its own pyproject.toml: name, version, description, licence, homepage,
# the Python it needs, its dependencies, its command. Nothing here is project-specific: a single
# package is the root's [project]; a workspace's members are [tool.uv.workspace]'s `members`
# (each a folder, or a `folder/*` glob of them). Each is a Python module, so a Python
# environment takes it; the command is its package as an application (toPythonApplication: the
# same derivation).
#
# A dependency that is a member is that member's package; any other is nixpkgs' Python package
# of its normalised name (python3Packages.<name>). One nixpkgs names otherwise, or one with
# extras, a marker or a URL -- which a name alone cannot honour -- fails evaluation naming it,
# until `overrides` below gives its packages.
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
        if glob == null && lib.hasInfix "*" member then
          throw "pyproject.toml: workspace member ${member}: only a folder, or folder/*, is read here"
        else if glob == null then
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
  # a requirement's packages where its name alone is not them, keyed by its normalised name: one
  # nixpkgs names otherwise, or with extras, a marker or a URL. For example:
  #   pywin32 = ps: [ ];                  (`; sys_platform == 'win32'`: nothing here)
  #   httpx = ps: [ ps.httpx ps.h2 ];     (`httpx[http2]`: the extra's packages too)
  overrides = { };
  # extras, a marker, a URL: what a name alone cannot honour
  plain = requirement: builtins.match ".*[][;@].*" requirement == null;
  # hatchling's license-files when [project] gives none (its metadata/core.py)
  hatchlingLicenceFiles = [
    "LICEN[CS]E*"
    "COPYING*"
    "NOTICE*"
    "AUTHORS*"
  ];
  # a file-name glob as a regex: `*`, `?`, `[...]` and `[!...]`, the rest literal
  globRegex =
    glob: lib.replaceStrings [ "\\*" "\\?" "\\[!" "\\[" ] [ ".*" "." "[^" "[" ] (lib.escapeRegex glob);

  manifests = map (
    folder:
    let
      manifest = lib.importTOML (folder + "/pyproject.toml");
    in
    {
      inherit folder;
      inherit (manifest) project;
      tool = manifest.tool or { };
    }
  ) folders;
  memberNames = map (m: normalise m.project.name) manifests;

  build =
    self:
    { folder, project, ... }:
    let
      # requires-python, a floor alone (">=3.13"): an older interpreter refused at evaluation
      floor =
        let
          matched = builtins.match ">=([0-9.]+)" project.requires-python;
        in
        lib.throwIf (matched == null) "${project.name}: requires-python is no floor alone" (
          lib.head matched
        );
      # the SPDX expression's licence identifiers: its operators, parentheses and `WITH`
      # exceptions aside
      licences = lib.subtractLists [ "" "AND" "OR" ] (
        lib.filter lib.isString (builtins.split "[ ()]+|WITH [^ ()]+" project.license)
      );
      scripts = project.scripts or { };
      # what hatchling reads besides the code: the readme, and the files license-files' globs
      # match at the package's top level, as hatchling globs them (a `*` here takes dotfiles too:
      # more in the source, never less) -- a file missing from the source is left out of the
      # wheel without a word. A symlink is refused: the source keeps it as a link, which no
      # longer resolves there.
      readme =
        if lib.isString (project.readme or null) then project.readme else project.readme.file or null;
      entries = lib.filterAttrs (_: type: type != "directory") (builtins.readDir folder);
      matching =
        glob:
        lib.throwIf (lib.hasInfix "/" glob)
          "${project.name}: license-files' ${glob} is below the package's top level, which alone is read here"
          (
            lib.filter (
              name:
              builtins.match (globRegex glob) name != null
              &&
                lib.throwIf (entries.${name} == "symlink")
                  "${project.name}: ${name} is a symlink, which its source would keep unresolved: copy the file"
                  true
            ) (lib.attrNames entries)
          );
      # hatchling's legacy table form too: { globs = [ ... ]; } or { paths = [ ... ]; }
      licenceGlobs =
        let
          declared = project.license-files or hatchlingLicenceFiles;
        in
        if lib.isAttrs declared then declared.globs or declared.paths or [ ] else declared;
      licenceFiles = lib.concatMap matching licenceGlobs;
      dependency =
        requirement:
        let
          name = requirementName requirement;
        in
        if lib.elem name memberNames then
          [ self.${name} ]
        else if overrides ? ${name} then
          overrides.${name} python3Packages
        else if !plain requirement then
          throw "${project.name}: ${requirement} has extras, a marker or a URL: give its packages in nix/packages.nix's overrides"
        else
          [
            python3Packages.${name}
              or (throw "${project.name}: nixpkgs has no python3Packages.${name} for ${requirement}: give its packages in nix/packages.nix's overrides")
          ];
    in
    python3Packages.buildPythonPackage {
      pname = project.name;
      inherit (project) version;
      src = lib.fileset.toSource {
        root = folder;
        fileset = lib.fileset.unions (
          [
            (folder + "/pyproject.toml")
            (folder + "/src")
          ]
          ++ map (name: folder + "/${name}") (lib.optional (readme != null) readme ++ licenceFiles)
        );
      };
      disabled = python3Packages.pythonOlder floor;
      pyproject = true;
      build-system = [ python3Packages.hatchling ];
      dependencies = lib.concatMap dependency (project.dependencies or [ ]);
      doCheck = false; # the tests run once, over every package: nix/checks.nix
      pythonImportsCheck = [ (lib.replaceStrings [ "-" ] [ "_" ] project.name) ];
      # nix/image.nix's labels: the SPDX expression as written (meta.license holds its
      # identifiers alone), and the repository (a member's homepage is its folder)
      passthru = {
        spdxLicense = project.license;
        repository = project.urls.Repository;
      };
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
  # the main package: a single package's own; a workspace's, its one member marked so in its own
  # [tool] table -- `[tool.<its name>] main = true` (tests/test_workspace.py holds it to one)
  marked = lib.filter (m: (m.tool.${m.project.name} or { }).main or false == true) manifests;
  main =
    if rootManifest ? project then
      rootManifest.project.name
    else if lib.length marked == 1 then
      (lib.head marked).project.name
    else
      throw "pyproject.toml: one workspace member is the main package, marked `[tool.<its name>] main = true` in its pyproject.toml (${toString (lib.length marked)} marked)";
  mainPackage = packages.${normalise main};
in
{
  inherit packages;
  # its command, when it has one, as an application (the same derivation)
  default =
    if mainPackage.meta ? mainProgram then
      python3Packages.toPythonApplication mainPackage
    else
      mainPackage;
}
