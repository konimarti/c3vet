#!/usr/bin/env bash
# The differential oracle (docs/ROADMAP.md section 6, point 4).
#
# c3vet promises zero overlap with the real compiler: every check this tool
# ships should be something c3c itself does not already catch. This script
# checks that promise empirically instead of by inspection:
#
#   1. run c3vet, with every check enabled, over the 642-file conformance
#      corpus, and record every (file, line, column) it reports a finding at.
#   2. run the real c3c compiler over the same files with its strictest
#      validation and warning flags, and record every (file, line, column) IT
#      reports a diagnostic at.
#   3. any (file, line, column) that appears in both lists is a bug in c3vet: it
#      means a check is just re-detecting something the compiler already
#      tells the user about.
#
# The corpus lives in a sibling checkout, found via C3C_CHECKOUT (same
# convention as test/parser/conformance.c3), default /home/km/Documents/c3c.
#
# usage: scripts/differential-oracle.sh
set -uo pipefail
cd "$(dirname "$0")/.."

CHECKOUT="${C3C_CHECKOUT:-/home/km/Documents/c3c}"
if [ ! -d "$CHECKOUT" ]; then
	echo "C3C_CHECKOUT not found at $CHECKOUT; skipping (nothing to compare against)"
	exit 0
fi

c3c build >/dev/null 2>&1
if [ ! -x build/c3vet ]; then
	echo "FAIL: build/c3vet did not build"
	exit 1
fi

files=$(find "$CHECKOUT/lib" "$CHECKOUT/test/unit" -name '*.c3' -o -name '*.c3i')

echo "1. running c3vet with every check enabled"
./build/c3vet --enable-all "$CHECKOUT/lib" "$CHECKOUT/test/unit" 2>/dev/null \
	| grep -oE '^[^:]+:[0-9]+:[0-9]+' > /tmp/c3vet_oracle_locs.txt
c3vet_count=$(wc -l < /tmp/c3vet_oracle_locs.txt)
echo "   $c3vet_count finding location(s)"

echo "2. running c3c with obnoxious validation over the same files"
# shellcheck disable=SC2086
c3c compile-only -C --validation=obnoxious $files > /tmp/c3c_oracle_raw.txt 2>&1
grep -oE '^[^:]+:[0-9]+:[0-9]+' /tmp/c3c_oracle_raw.txt > /tmp/c3c_oracle_locs.txt
c3c_count=$(wc -l < /tmp/c3c_oracle_locs.txt)
echo "   $c3c_count diagnostic location(s)"

echo "3. checking for overlap"
overlap=$(comm -12 <(sort -u /tmp/c3vet_oracle_locs.txt) <(sort -u /tmp/c3c_oracle_locs.txt))
if [ -n "$overlap" ]; then
	echo "   FAIL: c3vet and c3c agree at these locations -- a c3vet check is redundant with the compiler"
	echo "$overlap" | sed 's/^/     /'
	exit 1
fi
echo "   ok: no overlap"
exit 0
