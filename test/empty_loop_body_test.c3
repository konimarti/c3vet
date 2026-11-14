module c3vet::empty_loop_body_test @test;

import c3vet::testdata;
import c3vet;

fn void empty_loop_body()
{
	testdata::verify_check(c3vet::EMPTY_LOOP_BODY, "testdata/empty-loop-body.c3");
}
