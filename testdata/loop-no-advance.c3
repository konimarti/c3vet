module testdata_loop_no_advance;

fn void main()
{
	int i;
	int n = 10;
	int* p = &i;

	for (i = 0; i < n;) {        // want "loop condition never advances in the body"
	}

	for (i = 0; i < n; i++)
	{
	}

	for (i = 0; i < n;)
	{
		i += 1;
	}

	for (i = 0; i < n;)
	{
		i++;
	}

	for (i = 0; i < n;)
	{
		--i;
	}

	for (i = 0; i < n;)
	{
		p = &i;
	}

	for (i = 0; i < n;)
	{
		if (i == 5)
		{
			i = i + 1;
		}
	}

	for (;;)
	{
	}

	// Known false-positive class: the counter advances through the pointer
	// alias `p`, which this check cannot see through -- or the loop exits
	// via `break` before an advance is ever needed. Both are documented
	// limitations, not bugs in the check.
	// The finding below is the expected one for the `break` case.
	for (i = 0; i < n;) {        // want "loop condition never advances in the body"
		if (i == 5) break;
		*p = *p + 1;
	}
}
