module testdata_swallowed_fault;

fn int? maybe() => 1;

fn void main()
{
	if (catch maybe()) {} // want "fault is swallowed"
	if (catch maybe())
	{ // empty but documented
		// Deliberately ignored here.
	}
	if (catch maybe()) { int handled = 1; }
}
