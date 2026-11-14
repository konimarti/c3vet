module testdata_unused_try;

fn int? maybe() => 1;

fn void main()
{
	if (try value = maybe()) {} // want "try binding 'value'"
	if (try used = maybe()) { io::printfn("%d", used); }
}
