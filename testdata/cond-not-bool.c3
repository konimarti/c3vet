module testdata_cond_not_bool;

fn void f(int n, float* p, bool b)
{
	if (n) {}                       // want "condition 'n' is a declared 'int', not a boolean expression"
	while (n) { break; }            // want "condition 'n' is a declared 'int', not a boolean expression"
	if (p) {}                       // want "condition 'p' is a pointer, not a boolean expression"

	if (b) {}
	if (n > 0) {}
	if (n != 0) {}

	if (n) {} // c3vet:ignore[cond-not-bool]
}
