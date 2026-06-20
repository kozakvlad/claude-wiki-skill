#!/usr/bin/env python3
"""Migrate a wiki track from flat (modules/X.md) to folder layout
(modules/X/<main> + <facts_file> stub + required_dirs/.gitkeep). Idempotent and
conflict-safe: never deletes a flat file whose content diverges from an existing
main file. stdlib only.

Usage: wiki_migrate_folder.py --wiki <dir> --track <name>
Exit 0 ok (incl. conflicts reported), 2 usage/config error.
"""
import argparse, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wiki_config

_FACTS_STUB = ("---\ntype: %(type)s\n%(idfields)s---\n\n"
               "<!-- WIKI-AUTOGEN:start згенеровано автоматично з коду — не редагувати вручну -->\n"
               "<!-- WIKI-AUTOGEN:end -->\n")


def _read(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def _write(p, t):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(t)


def migrate(wiki, track):
    cfg = {t["dir"]: t for t in wiki_config.load_tracks(wiki)}
    tr = cfg.get(track)
    if not tr or tr.get("layout") != "folder":
        sys.stderr.write("track %r is not a folder-layout track\n" % track)
        return 2
    tdir = os.path.join(wiki, track)
    main, facts = tr["main"], tr["facts_file"]
    conflicts = []
    if os.path.isdir(tdir):
        entries = sorted(os.listdir(tdir))
        loose = {fn[:-3]: os.path.join(tdir, fn) for fn in entries
                 if fn.endswith(".md") and fn not in ("index.md", "log.md")}
        dirs = {fn for fn in entries if os.path.isdir(os.path.join(tdir, fn))}
        for entity in sorted(set(loose) | dirs):   # cover BOTH loose files and existing folders
            edir = os.path.join(tdir, entity)
            mainp = os.path.join(edir, main)
            # 1. fold a loose <entity>.md into the main file (conflict-safe)
            if entity in loose:
                loosep = loose[entity]
                if os.path.isfile(mainp):
                    if _read(mainp) != _read(loosep):
                        conflicts.append(entity)    # keep loose; resolve manually
                    else:
                        os.remove(loosep)           # identical -> already migrated
                else:
                    _write(mainp, _read(loosep)); os.remove(loosep)
            # 2. repair ANY entity folder (incl. the conflict case — do NOT skip):
            #    bring it to a lint-valid state per the track's full required set.
            if os.path.isdir(edir) or os.path.isfile(mainp):
                idf = "".join("%s: %s\n" % (r, entity) for r in tr.get("requires", []))
                # identity main file (if still missing — e.g. an empty pre-existing folder)
                if not os.path.isfile(mainp):
                    _write(mainp, "---\ntype: %s\n%s---\n# %s\n> TODO: опис.\n"
                                  % (tr["type"], idf, entity))
                # machine facts stub
                factsp = os.path.join(edir, facts)
                if not os.path.isfile(factsp):
                    _write(factsp, _FACTS_STUB % {"type": tr["type"], "idfields": idf})
                # any OTHER configured required_files -> safe member stub
                for rf in tr.get("required_files", []):
                    if rf in (main, facts):
                        continue
                    rfp = os.path.join(edir, rf)
                    if not os.path.isfile(rfp):
                        _write(rfp, "---\ntype: %s\n---\n# %s\n> TODO.\n" % (tr["type"], rf))
                for rd in tr.get("required_dirs", []):
                    gk = os.path.join(edir, rd, ".gitkeep")
                    if not os.path.exists(gk):
                        _write(gk, "")
    # rewrite flat links `(modules/X.md)` / `(/modules/X.md)` -> `.../X/<main>` in
    # EVERY wiki .md (index + all pages); idempotent (already-folder links don't match).
    pat = re.compile(r"\((/?)%s/([^/)#]+)\.md(#[^)]*)?\)" % re.escape(track))
    repl = lambda m: "(%s%s/%s/%s%s)" % (m.group(1), track, m.group(2), main, m.group(3) or "")
    for dp, _d, fs in os.walk(wiki):
        for fn in fs:
            if not fn.endswith(".md"):
                continue
            p = os.path.join(dp, fn)
            txt = _read(p); new = pat.sub(repl, txt)
            if new != txt:
                _write(p, new)
    if conflicts:
        sys.stderr.write("conflict (kept loose, resolve manually): %s\n" % ", ".join(conflicts))
    return 0


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--wiki", required=True)
    ap.add_argument("--track", required=True)
    args = ap.parse_args(argv[1:])
    try:
        return migrate(args.wiki, args.track)
    except wiki_config.ConfigError as e:
        sys.stderr.write("config error: %s\n" % e)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
