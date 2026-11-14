module testdata_contract_tautology;

<*
 @require n == n
*>
fn void f(int n) {}                  // want "@require compares an expression to itself"

<*
 @require n == m
*>
fn void g(int n, int m) {}

struct Pair { int a; int b; }

<*
 @require p.a == p.a
*>
fn void h(Pair p) {}                 // want "@require compares an expression to itself"

<*
 @require n > 0
*>
fn void k(int n) {}

fn void no_contract(int n) {}

<*
 @require n == n : "n must equal n"
*>
fn void m(int n) {}                  // want "@require compares an expression to itself"

<*
 @require n == n
*>
fn void suppressed(int n) {} // c3vet:ignore[contract-tautology]
