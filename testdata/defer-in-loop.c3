module testdata_defer_in_loop;

fn void catch_me() {}

fn void f()
{
	int[3] arr = { 1, 2, 3 };

	for (int i = 0; i < 10; i++)
	{
		defer catch_me();           // want "defer statement is lexically inside a loop body"
	}

	while (true)
	{
		defer catch_me();           // want "defer statement is lexically inside a loop body"
		break;
	}

	do
	{
		defer catch_me();           // want "defer statement is lexically inside a loop body"
	} while (false);

	foreach (x : arr)
	{
		defer catch_me();           // want "defer statement is lexically inside a loop body"
	}

	defer catch_me();

	for (int i = 0; i < 10; i++)
	{
		defer catch_me(); // c3vet:ignore[defer-in-loop]
	}
}
