module testdata_silenced_fault;

fn int? maybe() => 1;
fn int ordinary() => 1;

fn void main()
{
	(void)maybe(); // want "void cast discards an Optional result"
	(void)ordinary();
	(void)testdata_silenced_fault::maybe(); // want "void cast discards an Optional result"
}
