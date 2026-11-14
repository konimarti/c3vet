module testdata_self_op;

fn void f(int a, int b, int[] arr, int i)
{
	int r1;
	int r2;
	int r3;
	int r4;
	int r5;
	int r6;
	int r7;
	int r8;
	int r9;
	r1 = a - a;              // want "self-operation"
	r2 = a / a;              // want "self-operation"
	r3 = a % a;              // want "self-operation"
	r4 = a ^ a;              // want "self-operation"
	r5 = a & a;              // want "self-operation"
	r6 = a | a;              // want "self-operation"
	r7 = a - b;              // no diagnostic expected
	r8 = arr[i] - arr[i];    // want "self-operation"
	r9 = arr[i] - arr[i + 1]; // no diagnostic expected

	// Other binary operators are out of scope for self-op.
	int r10;
	int r11;
	r10 = a + a;
	r11 = a * a;

	// The side-effect guard.
	int r12;
	r12 = foo() - foo();
}

fn int foo() => 0;
