set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIG="$ROOT/scripts/wiki_migrate_folder.py"
fail=0
mkwiki() {
  w="$(mktemp -d)"; mkdir -p "$w/modules"
  printf -- '---\ntype: reference\ntracks:\n  - dir: modules\n    type: module\n    requires: [module]\n    layout: folder\n    main: overview.md\n    facts_file: facts.md\n    required_files: [overview.md]\n    required_dirs: [decisions]\n---\n' > "$w/schema.md"
  printf -- '# Index\n- [foo](modules/foo.md) — the foo module.\n' > "$w/index.md"
  printf '# Log\n' > "$w/log.md"
  printf -- '---\ntype: module\nmodule: foo\n---\n# foo\nHuman prose about foo.\n' > "$w/modules/foo.md"
  echo "$w"
}
run() { python3 "$MIG" --wiki "$1" --track modules >"$2" 2>&1; echo $?; }
# A: migrate flat foo.md -> folder.
W="$(mkwiki)"; out="$(mktemp)"; rc="$(run "$W" "$out")"
[ "$rc" = "0" ] || { echo "FAIL A (rc=$rc):"; cat "$out"; fail=1; }
[ -f "$W/modules/foo/overview.md" ] || { echo "FAIL A overview"; fail=1; }
[ -f "$W/modules/foo/decisions/.gitkeep" ] || { echo "FAIL A decisions"; fail=1; }
[ ! -f "$W/modules/foo.md" ] || { echo "FAIL A loose still present"; fail=1; }
grep -q "Human prose about foo" "$W/modules/foo/overview.md" || { echo "FAIL A prose lost"; fail=1; }
grep -q "modules/foo/overview.md" "$W/index.md" || { echo "FAIL A index not rewritten"; fail=1; }
# B: idempotent — second run no error, no change.
before="$(find "$W/modules" -type f | sort; cat "$W/index.md")"
run "$W" "$(mktemp)" >/dev/null
after="$(find "$W/modules" -type f | sort; cat "$W/index.md")"
[ "$before" = "$after" ] || { echo "FAIL B (not idempotent)"; fail=1; }
# C: conflict — overview exists and differs from leftover loose foo.md -> loose kept, reported.
W2="$(mkwiki)"; mkdir -p "$W2/modules/foo"
printf -- '---\ntype: module\nmodule: foo\n---\n# foo\nDIFFERENT prose.\n' > "$W2/modules/foo/overview.md"
out="$(mktemp)"; rc="$(run "$W2" "$out")"
[ -f "$W2/modules/foo.md" ] || { echo "FAIL C (loose deleted on conflict)"; fail=1; }
grep -qi "conflict" "$out" || { echo "FAIL C (conflict not reported):"; cat "$out"; fail=1; }
# conflict must NOT skip repair: facts.md + decisions/ still created.
[ -f "$W2/modules/foo/facts.md" ] || { echo "FAIL C (facts not created on conflict)"; fail=1; }
[ -f "$W2/modules/foo/decisions/.gitkeep" ] || { echo "FAIL C (decisions not created on conflict)"; fail=1; }
# D: already-folder entity missing facts.md/decisions (no loose file) -> repaired.
W3="$(mkwiki)"; rm "$W3/modules/foo.md"; mkdir -p "$W3/modules/foo"
printf -- '---\ntype: module\nmodule: foo\n---\n# foo\nprose\n' > "$W3/modules/foo/overview.md"
run "$W3" "$(mktemp)" >/dev/null
[ -f "$W3/modules/foo/facts.md" ] || { echo "FAIL D (facts not repaired)"; fail=1; }
[ -f "$W3/modules/foo/decisions/.gitkeep" ] || { echo "FAIL D (decisions not repaired)"; fail=1; }
# E: no stale modules/X.md links remain in index after migration (Case A wiki).
grep -q "(modules/foo.md)" "$W/index.md" && { echo "FAIL E (stale flat link in index)"; fail=1; }
# F: a flat link inside ANOTHER page (not index) is rewritten too.
WF="$(mkwiki)"
printf -- '---\ntype: module\nmodule: bar\n---\n# bar\nSee [foo](modules/foo.md).\n' > "$WF/modules/bar.md"
run "$WF" "$(mktemp)" >/dev/null
grep -q "(modules/foo/overview.md)" "$WF/modules/bar/overview.md" || { echo "FAIL F (cross-page link not rewritten):"; cat "$WF/modules/bar/overview.md"; fail=1; }
grep -q "(modules/foo.md)" "$WF/modules/bar/overview.md" && { echo "FAIL F (stale link remains in page)"; fail=1; }
# G: an EXTRA configured required_file (notes.md) is stubbed during migration.
WG="$(mktemp -d)"; mkdir -p "$WG/modules"
printf -- '---\ntype: reference\ntracks:\n  - dir: modules\n    type: module\n    requires: [module]\n    layout: folder\n    main: overview.md\n    facts_file: facts.md\n    required_files: [overview.md, facts.md, notes.md]\n    required_dirs: [decisions]\n---\n' > "$WG/schema.md"
printf '# Index\n' > "$WG/index.md"; printf '# Log\n' > "$WG/log.md"
printf -- '---\ntype: module\nmodule: foo\n---\n# foo\nprose\n' > "$WG/modules/foo.md"
run "$WG" "$(mktemp)" >/dev/null
[ -f "$WG/modules/foo/notes.md" ] || { echo "FAIL G (extra required_file not stubbed)"; fail=1; }
grep -q "^type:" "$WG/modules/foo/notes.md" || { echo "FAIL G (notes stub missing type)"; fail=1; }
# H: a flat link WITH an anchor is rewritten and the anchor is preserved.
WH="$(mkwiki)"
printf -- '---\ntype: module\nmodule: bar\n---\n# bar\nSee [foo](modules/foo.md#models).\n' > "$WH/modules/bar.md"
run "$WH" "$(mktemp)" >/dev/null
grep -q "(modules/foo/overview.md#models)" "$WH/modules/bar/overview.md" || { echo "FAIL H (anchor link not rewritten):"; cat "$WH/modules/bar/overview.md"; fail=1; }
[ "$fail" = "0" ] && echo "wiki_migrate_folder_test: PASS"
exit "$fail"
