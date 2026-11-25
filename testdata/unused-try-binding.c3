module testdata_unused_try;

fn int? maybe() => 1;

fn void main()
{
	if (try value = maybe()) // want "try binding 'value'"
	{}
	if (try used = maybe())
	{
		io::printfn("%d", used);
	}
	if (try guard = maybe() && guard > 0)
	{}
	if (try first = maybe() && first > 0 && true)
	{}
	if (try int typed = maybe() && typed > 0)
	{}
	if (try lone = maybe() && true) // want "try binding 'lone'"
	{}
}
