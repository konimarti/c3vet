module testdata_self_assign;

struct Obj { int f; }

fn void f(int count, Obj obj, int[] arr, int i)
{
	count = count;              // want "self-assignment"
	count = count + 1;          // no diagnostic expected

	obj.f = obj.f;               // want "self-assignment"
	obj.f = obj.f + 1;           // no diagnostic expected

	arr[i] = arr[i];             // want "self-assignment"
	arr[i] = arr[i + 1];         // no diagnostic expected

	// Compound assignment changes the value -- not self-assignment.
	count += count;

	// A call on either side may not be pure -- never flag it.
	count = foo();
}

fn int foo() => 0;
