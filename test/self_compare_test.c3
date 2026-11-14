module c3vet::self_compare_test @test;

import c3vet::testdata;
import c3vet;

fn void self_compare()
{
	testdata::verify_check(c3vet::SELF_COMPARE, "testdata/self-compare.c3");
}
