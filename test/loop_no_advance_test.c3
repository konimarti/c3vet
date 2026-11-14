module c3vet::loop_no_advance_test @test;

import c3vet::testdata;
import c3vet;

fn void loop_no_advance()
{
	testdata::verify_check(c3vet::LOOP_NO_ADVANCE, "testdata/loop-no-advance.c3");
}
