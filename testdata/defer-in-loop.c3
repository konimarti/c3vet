module testdata_defer_in_loop;

fn void catch_me() {}

fn void f()
{
	int[3] arr = { 1, 2, 3 };

	for (int i = 0; i < 10; i++)
	{
		defer catch_me();           // want "defer inside a loop body runs every iteration, not once at the end"
	}

	while (true)
	{
		defer catch_me();           // want "defer inside a loop body runs every iteration, not once at the end"
		break;
	}

	do
	{
		defer catch_me();           // want "defer inside a loop body runs every iteration, not once at the end"
	} while (false);

	foreach (x : arr)
	{
		defer catch_me();           // want "defer inside a loop body runs every iteration, not once at the end"
	}

	defer catch_me();

	for (int i = 0; i < 10; i++)
	{
		defer catch_me(); // c3vet:ignore[defer-in-loop]
	}
}
