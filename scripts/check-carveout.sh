#!/usr/bin/env bash
# Enforce the parser carve-out contract (docs/DESIGN.md section 1.5).
#
# src/parser/ must stay liftable into its own parser.c3l. A green `c3c build`
# of the whole project does NOT demonstrate that, because the parser would
# still compile with c3vet sitting next to it. Two gates are needed:
#
#   1. the `parser` target builds src/parser/ alone
#   2. no file under src/parser/ imports c3vet, or names a c3vet type
#
# usage: scripts/check-carveout.sh
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0

echo "1. building the parser alone"
rm -f build/parser.a
if c3c build parser >/dev/null 2>&1 && [ -f build/parser.a ]; then
	echo "   ok: build/parser.a"
else
	echo "   FAIL: src/parser/ does not build on its own"
	c3c build parser 2>&1 | grep -E "error:" | head -5
	fails=$((fails + 1))
fi

echo "2. checking for reverse dependencies"
if bad=$(grep -rnE '^[[:space:]]*import[[:space:]].*\bc3vet\b' src/parser/ 2>/dev/null); then
	echo "   FAIL: src/parser/ imports c3vet"
	echo "$bad" | sed 's/^/     /'
	fails=$((fails + 1))
else
	echo "   ok: no c3vet imports"
fi

# Rule 2: the parser must not name a c3vet type. Catching this by name is
# cruder than the build gate but reports the real cause, not a cascade.
# Comments are stripped first: these names are discussed in the doc comments
# precisely because they are forbidden in the code.
strip_comments() {
	awk '
		{ line = $0 }
		# Drop whole-line and trailing // comments.
		{ sub(/\/\/.*$/, "", line) }
		# Track <* ... *> doc-comment blocks.
		{
			while (1) {
				if (indoc) {
					e = index(line, "*>")
					if (e == 0) { line = ""; break }
					line = substr(line, e + 2); indoc = 0
				} else {
					b = index(line, "<*")
					if (b == 0) break
					rest = substr(line, b + 2); line = substr(line, 1, b - 1)
					e = index(rest, "*>")
					if (e == 0) { indoc = 1; break }
					line = line substr(rest, e + 2)
				}
			}
			printf "%s:%d:%s\n", FILENAME, FNR, line
		}
	' "$@"
}

borrowed='\b(Diagnostic|DiagnosticList|Check|CheckFn|Ctx|Config|Unit|Tier|Scopes|Flow|DeclTable|SuppressionSet)\b'
if bad=$(strip_comments $(find src/parser -name '*.c3') | grep -E "$borrowed"); then
	echo "   FAIL: src/parser/ names a c3vet type (DESIGN 1.5 rule 2)"
	echo "$bad" | sed 's/^/     /'
	fails=$((fails + 1))
else
	echo "   ok: no borrowed types"
fi

echo
[ "$fails" -eq 0 ] && { echo "carve-out intact"; exit 0; }
echo "$fails carve-out violation(s)"
exit 1
