module testdata_stub_empty_block;

fn void main()
{
	{                        // want "empty block"
	}

	{
		foo;
	}

	{                        // c3vet:ignore[stub-empty-block]
	}

	{ }                      // want "empty block"
}
