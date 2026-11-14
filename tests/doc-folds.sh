#!/bin/sh
# tests/doc-folds.sh -- every section of docs/delve.md is folded shut.
#
# docs/delve.md gives away what the game asks a player to work out, so each
# `## ` section's text sits in a <details> block, closed where GitHub renders
# it.  This fails when a section's first line is anything else, or when the
# blocks opened and closed do not match.
set -e

DOC="$(cd "$(dirname "$0")/.." && pwd)/docs/delve.md"

awk '
/^## /        { if (want) bad[++n] = head; want = 1; head = $0; next }
want && /^$/  { next }
want          { if ($0 != "<details>") bad[++n] = head; want = 0 }
/^<details>$/  { opened++ }
/^<\/details>$/ { closed++ }
END {
	if (want) bad[++n] = head
	for (i = 1; i <= n; i++) print "doc-folds: not folded: " bad[i]
	if (opened != closed)
		print "doc-folds: " opened " <details> opened, " closed " closed"
	exit (n > 0 || opened != closed)
}' "$DOC"

echo "doc-folds: ok -- every section of docs/delve.md is folded"
