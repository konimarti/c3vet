#!/usr/bin/env bash
# Probe c3c for overlap with c3vet's planned checks.
#
# c3vet never reimplements a diagnostic the compiler already produces, so
# overlap is a bug. This script is the oracle for that rule: each case is an
# isolated, otherwise-clean file holding one suspicious construct. A case
# marked GAP must produce no c3c diagnostic at any validation level; a case
# marked COVERED must produce one.
#
# Run it before implementing a check and in CI, so that
# c3c adopting a check upstream shows up as a failure here rather than as
# silent duplication in c3vet.
#
# usage: scripts/probe-overlap.sh [-v]
set -uo pipefail

VERBOSE=${1:-}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fails=0
total=0

# probe <name> <expected: GAP|COVERED> <body>
probe() {
	local name=$1 expect=$2 body=$3
	local f="$WORK/$name.c3"
	printf 'module probe_%s;\nimport std::io;\n%s\n' "$name" "$body" > "$f"
	total=$((total + 1))

	local msg=""
	for level in "" "--validation=strict" "--validation=obnoxious"; do
		local out
		out=$(c3c compile-only --no-entry -C $level "$f" 2>&1 \
			| grep -E "$name\.c3:[0-9]+:[0-9]+: (error|warning)" | head -1)
		if [ -n "$out" ]; then msg=${out##*"$name.c3:"}; break; fi
	done

	local got="GAP"
	[ -n "$msg" ] && got="COVERED"

	if [ "$got" = "$expect" ]; then
		[ -n "$VERBOSE" ] && printf '  ok   %-26s %s\n' "$name" "$got"
	else
		printf '  FAIL %-26s expected %s, got %s  %s\n' "$name" "$expect" "$got" "$msg"
		fails=$((fails + 1))
	fi
}

echo "c3c: $(c3c --version 2>&1 | head -1 | sed 's/.*Version: *//')"
echo
echo "Syntactic checks -- every one must still be a GAP:"

# --- Family C: copy-paste and self-reference ---
probe self_assign  GAP 'fn void f() { int a = 5; a = a; io::printn(a); }'
probe self_compare GAP 'fn void f(int a) { if (a == a) io::printn("x"); }'
probe self_op      GAP 'fn void f(int a) { int b = a - a; io::printn(b); }'
probe dup_branch   GAP 'fn void f(int a) { if (a > 1) { io::printn("A"); } else if (a > 1) { io::printn("A"); } }'

# --- Family D/E: conditions and loop intent ---
probe const_cond      GAP 'fn void f() { if (1 == 2) io::printn("x"); }'
probe empty_body      GAP 'fn void f(int a) { if (a > 1) {} }'
probe loop_no_advance GAP 'fn void f() { for (int i = 0; i < 3;) { io::printn("x"); } }'
probe empty_loop_body GAP 'fn void f() { for (int i = 0; i < 3; i++) {} }'
probe unused_label    GAP 'fn void f() { while FOO: (true) { io::printn("x"); break; } }'

# --- Family H: constant arithmetic ---
probe const_int_div   GAP 'fn void f() { float g = 1 / 2; io::printfn("%f", g); }'
probe const_narrowing GAP 'fn void f() { long big = 100000; char small = (char)big; io::printn(small); }'

echo
echo "Control group -- c3c must still cover these, or this list is stale:"
probe c_shadow        COVERED 'fn void f() { int x = 1; { int x = 2; io::printn(x); } io::printn(x); }'
probe c_printf_few    COVERED 'fn void f(int a) { io::printfn("%s %s", a); }'
probe c_return_local  COVERED 'fn int* f() { int local = 7; return &local; }'
probe c_unsigned_lt   COVERED 'fn void f(usz u) { if (u < 0) io::printn("x"); }'
probe c_dead_code     COVERED 'fn void f() { io::printn("a"); return; io::printn("b"); }'
probe c_dup_case      COVERED 'fn void f(int a) { switch (a) { case 1: io::printn("x"); case 1: io::printn("y"); default: break; } }'
probe c_dup_member    COVERED 'struct Thing { int alpha; int alpha; }
fn void f(Thing t) { t.alpha = 1; }'
probe c_dup_import    COVERED 'import std::io;
fn void f() { io::printn("x"); }'
probe c_bad_attr      COVERED 'fn void f() @inlined { io::printn("x"); }'
probe c_missing_case  COVERED 'enum Color { RED, GREEN, BLUE }
fn void f(Color c) { switch (c) { case RED: io::printn("r"); case GREEN: io::printn("g"); } }'
probe c_test_param    COVERED 'fn void check(int n) @test { }'
probe c_opt_unhandled COVERED 'fn int? risky() { return 1; }
fn void f() { risky(); }'

echo
if [ "$fails" -eq 0 ]; then
	echo "all $total probes as expected"
	exit 0
fi
echo "$fails of $total probes disagree with expectations -- update the probes"
exit 1
