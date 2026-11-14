module testdata_unused_catch;

fn int? maybe() => 1;

fn void main()
{
	if (catch err = maybe()) {} // want "catch binding 'err'"
	if (catch used = maybe()) { io::printfn("%d", used); }
}
