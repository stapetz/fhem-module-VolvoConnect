#!/usr/bin/env python3
"""Release a single module from dev to main with its own version number.

Usage: scripts/release.py <modul> <version> [-m "Zeile"]... [--push]

<modul>   key from MODULES in generate_changed.py (e.g. dashboardhub, solax)
<version> semantic version without suffix, e.g. 1.0.0

Steps (run from a clean checkout; the current branch must be dev):
 1. switch to main and take the module file and docs/<modul> from dev
 2. set the version in the module file (removes the -dev suffix)
 3. commit "Release <Modul> <version>" (the -m lines become the changelog summary)
    and tag <modul>-v<version>
 4. switch back to dev and set the next development version (<patch+1>-dev)
Without --push nothing is sent to origin; the commands are printed instead.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_changed import MODULES  # noqa: E402

VERSION_LINE = re.compile(r"^(our \$\w*VERSION\s*=\s*')([^']*)(';)", re.M)
TRAILER = "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"


def git(*args, check=True):
    return subprocess.run(["git", *args], check=check, text=True,
                          capture_output=True).stdout.strip()


def set_version(path, version):
    text = Path(path).read_text(encoding="utf-8")
    new, count = VERSION_LINE.subn(lambda m: m.group(1) + version + m.group(3), text, count=1)
    if count != 1:
        sys.exit(f"Keine Versionszeile (our $...VERSION = '...';) in {path} gefunden")
    Path(path).write_text(new, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("module", choices=sorted(MODULES))
    parser.add_argument("version")
    parser.add_argument("-m", "--note", action="append", default=[],
                        help="Zeile fuer das Aenderungsprotokoll (mehrfach moeglich)")
    parser.add_argument("--push", action="store_true", help="main, Tag und dev nach origin pushen")
    args = parser.parse_args()

    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        sys.exit("Version muss das Format X.Y.Z haben")
    name, paths = MODULES[args.module]
    module_file = paths[0]
    tag = f"{args.module}-v{args.version}"

    if git("rev-parse", "--abbrev-ref", "HEAD") != "dev":
        sys.exit("Bitte auf dem Branch dev starten")
    if git("status", "--porcelain"):
        sys.exit("Arbeitsverzeichnis ist nicht sauber (erst committen)")
    if git("tag", "-l", tag):
        sys.exit(f"Tag {tag} existiert bereits")

    nxt = args.version.split(".")
    nxt[2] = str(int(nxt[2]) + 1)
    next_dev = ".".join(nxt) + "-dev"

    try:
        git("checkout", "main")
        git("pull", "--rebase", check=False)
        git("checkout", "dev", "--", *paths)
        set_version(module_file, args.version)
        git("add", "--", *paths)
        message = f"Release {name} {args.version}\n\n" + "".join(f"{n}\n" for n in args.note)
        git("commit", "-m", message + "\n" + TRAILER)
        git("tag", "-a", tag, "-m", f"{name} {args.version}")
    finally:
        git("checkout", "dev")

    set_version(module_file, next_dev)
    git("add", module_file)
    git("commit", "-m", f"Entwicklung {name} {next_dev}\n\n{TRAILER}")

    if args.push:
        git("push", "origin", "main", tag)
        git("pull", "--rebase", "--autostash", check=False)
        git("push", "origin", "dev")
        print(f"{name} {args.version} auf main veroeffentlicht (Tag {tag}); dev steht auf {next_dev}")
    else:
        print(f"{name} {args.version} lokal veroeffentlicht (Tag {tag}); dev steht auf {next_dev}")
        print("Zum Veroeffentlichen: git push origin main " + tag + " && git push origin dev")


if __name__ == "__main__":
    main()
