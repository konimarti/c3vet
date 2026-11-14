module testdata_self_compare;

fn void f(int a, int b, int* p)
{
	bool r1;
	bool r2;
	bool r3;
	bool r4;
	bool r5;
	r1 = a == a;            // want "self-comparison"
	r2 = a != a;            // want "self-comparison"
	r3 = a < a;             // want "self-comparison"
	r4 = a >= a;            // want "self-comparison"
	r5 = a == b;            // no diagnostic expected

	// The side-effect guard: none of these are guaranteed to read the same
	// value twice, so none of them may fire.
	bool r6;
	bool r7;
	bool r8;
	r6 = foo() == foo();
	r7 = (*p) == (*p);
	int c = a;
	r8 = c++ == c++;
}

fn int foo() => 0;
