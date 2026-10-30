#!/usr/bin/env python3
"""Generate CHANGED (whole package) and CHANGED_<module> files from Git history.

Each commit becomes one entry: date, hash, subject and the commit body lines as
summary. Per-module files only list commits that touched the module's files.
Output is ASCII-only with lines of at most 79 characters (FHEM update format).
"""
import subprocess
import textwrap
import unicodedata
from pathlib import Path

MODULES = {
    "volvo": ("VolvoConnect", ["FHEM/50_VolvoConnect.pm", "docs/volvo"]),
    "temperaturecollector": (
        "TemperatureCollector",
        ["FHEM/50_TemperatureCollector.pm", "docs/temperaturecollector"],
    ),
    "gavazzi": ("GavazziEM24", ["FHEM/70_GavazziEM24.pm", "docs/gavazzi"]),
    "solax": ("SolaxModbus", ["FHEM/98_ModbusSolax.pm", "docs/solax"]),
    "dashboardhub": (
        "DashboardHub",
        ["FHEM/50_DashboardHub.pm", "docs/dashboardhub"],
    ),
}
WIDTH = 79
TRAILERS = ("co-authored-by:", "signed-off-by:")


def commits(paths=None):
    cmd = ["git", "log", "--no-merges", "--date=short",
           "--pretty=format:%h%x1f%ad%x1f%s%x1f%b%x1e"]
    if paths:
        cmd += ["--"] + paths
    out = subprocess.check_output(cmd, text=True)
    for record in out.split("\x1e"):
        record = record.strip("\n")
        if not record:
            continue
        sha, date, subject, body = record.split("\x1f", 3)
        if "[skip ci]" in subject or subject.startswith("Automated update of"):
            continue
        yield sha.strip(), date, subject.strip(), body.strip()


def category(subject):
    lower = subject.lower()
    if lower.startswith(("fix", "bugfix")):
        return "bugfix"
    if lower.startswith(("feat", "feature")):
        return "feature"
    if lower.startswith(("doc", "documentation")):
        return "documentation"
    return "change"


def ascii_text(text):
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")


def wrap(text, indent="  "):
    return textwrap.wrap(ascii_text(text), width=WIDTH, subsequent_indent=indent,
                         break_long_words=False, break_on_hyphens=False)


def render(title, entries, tags=False):
    lines = [
        f"# {title} change history",
        "# Generated from Git commits by scripts/generate_changed.py.",
        "# Keep this file ASCII-only and use lines no longer than 79 characters.",
        "",
    ]
    for sha, date, subject, body, modules in entries:
        tag = f" [{', '.join(modules)}]" if tags and modules else ""
        lines += wrap(f"- {category(subject)}: {date} {sha} {subject}{tag}")
        for raw in body.splitlines():
            raw = raw.strip()
            if raw and not raw.lower().startswith(TRAILERS):
                lines += wrap("  " + raw.lstrip("-* ").strip(), "    ")
    return "\n".join(lines) + "\n"


def main():
    per_module = {}
    for key, (label, paths) in MODULES.items():
        per_module[key] = {sha for sha, *_ in commits(paths)}
        entries = [(s, d, subj, b, []) for s, d, subj, b in commits(paths)]
        Path(f"CHANGED_{key}").write_text(render(label, entries), encoding="ascii")

    entries = []
    for sha, date, subject, body in commits():
        touched = [MODULES[k][0] for k in MODULES if sha in per_module[k]]
        entries.append((sha, date, subject, body, touched))
    Path("CHANGED").write_text(render("FHEM modules", entries, tags=True), encoding="ascii")


if __name__ == "__main__":
    main()
