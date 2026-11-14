module testdata_empty_body;

fn void main()
{
	int c = 1;

	if (c == 1) {}                 // want "empty body"

	while (c == 1) {}              // want "empty body"

	if (c == 1)
	{
		// explains why this is deliberately left blank
	}

	while (c == 1)
	{
		c = 0;
	}

	if (c == 1) {} else { c = 2; } // want "empty body"

	if (c == 1) {}                 // c3vet:ignore[empty-body]

	if (c == 1) { c = 2; } else {} // want "empty body"
}
