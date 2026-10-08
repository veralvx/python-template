// cargo-generate's pre hook (cargo-generate.toml's [hooks]): the project name, `-` as `_`, is
// the import name, so it must be a Python identifier -- ASCII, as a PyPI name is -- and no
// keyword (the language reference's list, 3.12-3.14). Refused here, it fails before a file is
// written; past here, only ruff and pytest would say so. The hook is not copied into the project.
let name = variable::get("crate_name");
let keywords = [
    "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
    "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if",
    "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try",
    "while", "with", "yield",
];
let identifier = name.len() > 0;
for (c, i) in name.chars() {
    let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
    if !(letter || (i > 0 && c >= '0' && c <= '9')) {
        identifier = false;
    }
}
if !identifier || keywords.contains(name) {
    abort(`the import name "${name}" is no Python identifier, or is a keyword: choose another project name`);
}
