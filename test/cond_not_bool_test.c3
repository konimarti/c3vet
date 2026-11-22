module c3vet::cond_not_bool_test @test;

import c3vet;
import c3vet::testdata;

fn void cond_not_bool()
{
	testdata::verify_check(c3vet::COND_NOT_BOOL, "testdata/cond-not-bool.c3");
}
