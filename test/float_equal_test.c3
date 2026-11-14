module c3vet::float_equal_test @test;

import c3vet::testdata;
import c3vet;

fn void float_equal()
{
	testdata::verify_check(c3vet::FLOAT_EQUAL, "testdata/float-equal.c3");
}
