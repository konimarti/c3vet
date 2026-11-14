module testdata_empty_loop_body;

fn bool side_effect() => true;

fn int[] get_arr() => { 1, 2, 3 };

fn void main()
{
	int i;
	int[3] arr = { 1, 2, 3 };

	while (true) {               // want "empty loop body"
	}

	for (;;) {                   // want "empty loop body"
	}

	for (i = 0; i < 10; i++) {   // want "empty loop body"
	}

	do {                         // want "empty loop body"
	} while (i < 10);

	foreach (x : arr) {          // want "empty loop body"
	}

	while (side_effect()) {
	}

	do
	{
	} while (side_effect());

	foreach (x : get_arr()) {
	}

	while (i++ < 10) {
	}

	while (true)
	{
		i = i + 1;
	}
}
