module c3vet::const_cond_test @test;

import c3vet;
import c3vet::testdata;

fn void const_cond()
{
	testdata::verify_check(c3vet::CONST_COND, "testdata/const-cond.c3");
}
