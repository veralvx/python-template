// cargo-generate's pre hook (cargo-generate.toml's [hooks]): the project name, `-` as `_`, is
// the import name. Refused here, before a file is written -- past here only ruff and pytest would
// say so -- a name that is:
//   - no ASCII Python identifier (a PyPI name is ASCII): `3d-tool` would not parse;
//   - a keyword (the language reference's list, 3.12-3.14): `async`;
//   - a standard-library module (sys.stdlib_module_names, 3.12-3.14, lowercase): the import
//     would find the standard library's first, as an editable install appends to sys.path.
// cargo-generate runs the hook from the template and does not copy it into the project.
let name = variable::get("crate_name");
let keywords = [
    "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue",
    "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import",
    "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
    "with", "yield",
];
let stdlib = [
    "abc", "aifc", "annotationlib", "antigravity", "argparse", "array", "ast", "asyncio", "atexit",
    "audioop", "base64", "bdb", "binascii", "bisect", "builtins", "bz2", "calendar", "cgi", "cgitb",
    "chunk", "cmath", "cmd", "code", "codecs", "codeop", "collections", "colorsys", "compileall",
    "compression", "concurrent", "configparser", "contextlib", "contextvars", "copy", "copyreg",
    "crypt", "csv", "ctypes", "curses", "dataclasses", "datetime", "dbm", "decimal", "difflib",
    "dis", "doctest", "email", "encodings", "ensurepip", "enum", "errno", "faulthandler", "fcntl",
    "filecmp", "fileinput", "fnmatch", "fractions", "ftplib", "functools", "gc", "genericpath",
    "getopt", "getpass", "gettext", "glob", "graphlib", "grp", "gzip", "hashlib", "heapq", "hmac",
    "html", "http", "idlelib", "imaplib", "imghdr", "importlib", "inspect", "io", "ipaddress",
    "itertools", "json", "keyword", "lib2to3", "linecache", "locale", "logging", "lzma", "mailbox",
    "mailcap", "marshal", "math", "mimetypes", "mmap", "modulefinder", "msilib", "msvcrt",
    "multiprocessing", "netrc", "nis", "nntplib", "nt", "ntpath", "nturl2path", "numbers", "opcode",
    "operator", "optparse", "os", "ossaudiodev", "pathlib", "pdb", "pickle", "pickletools", "pipes",
    "pkgutil", "platform", "plistlib", "poplib", "posix", "posixpath", "pprint", "profile",
    "pstats", "pty", "pwd", "py_compile", "pyclbr", "pydoc", "pydoc_data", "pyexpat", "queue",
    "quopri", "random", "re", "readline", "reprlib", "resource", "rlcompleter", "runpy", "sched",
    "secrets", "select", "selectors", "shelve", "shlex", "shutil", "signal", "site", "smtplib",
    "sndhdr", "socket", "socketserver", "spwd", "sqlite3", "sre_compile", "sre_constants",
    "sre_parse", "ssl", "stat", "statistics", "string", "stringprep", "struct", "subprocess",
    "sunau", "symtable", "sys", "sysconfig", "syslog", "tabnanny", "tarfile", "telnetlib",
    "tempfile", "termios", "textwrap", "this", "threading", "time", "timeit", "tkinter", "token",
    "tokenize", "tomllib", "trace", "traceback", "tracemalloc", "tty", "turtle", "turtledemo",
    "types", "typing", "unicodedata", "unittest", "urllib", "uu", "uuid", "venv", "warnings",
    "wave", "weakref", "webbrowser", "winreg", "winsound", "wsgiref", "xdrlib", "xml", "xmlrpc",
    "zipapp", "zipfile", "zipimport", "zlib", "zoneinfo",
];
let identifier = name.len() > 0;
for (c, i) in name.chars() {
    let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
    if !(letter || (i > 0 && c >= '0' && c <= '9')) {
        identifier = false;
    }
}
if !identifier || keywords.contains(name) {
    abort(`import name "${name}": no Python identifier, or a keyword -- choose another name`);
}
if stdlib.contains(name) {
    abort(`import name "${name}": a standard-library module's -- choose another name`);
}
