module c3vet::const_narrowing_overflow_test @test;

import c3vet;
import c3vet::testdata;

fn void const_narrowing_overflow()
{
	testdata::verify_check(c3vet::CONST_NARROWING_OVERFLOW, "testdata/const-narrowing-overflow.c3");
}
