module c3vet::stub_check_test @test;

import c3vet::testdata;

<*
 Proves the harness works end to end: a wanted finding is matched, a
 non-empty block produces nothing, and a suppressed one is not reported.
*>
fn void stub_empty_block()
{
	testdata::verify("stub-empty-block", "testdata/stub-empty-block.c3");
}
