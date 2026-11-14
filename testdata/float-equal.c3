module testdata_float_equal;

fn void f(float x, double y, int n)
{
	if (x == 1.0) {}                // want "== or != compares floating-point values"
	if (y != 2.0) {}                // want "== or != compares floating-point values"
	if (n == 1.5) {}                // want "== or != compares floating-point values"
	if (x == y) {}                  // want "== or != compares floating-point values"

	float z = 3.0;
	if (z == x) {}                  // want "== or != compares floating-point values"

	if (n == 1) {}

	if (x == 1.0) {} // c3vet:ignore[float-equal]
}
