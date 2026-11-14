module c3vet::defer_in_loop_test @test;

import c3vet::testdata;
import c3vet;

fn void defer_in_loop()
{
	testdata::verify_check(c3vet::DEFER_IN_LOOP, "testdata/defer-in-loop.c3");
}
