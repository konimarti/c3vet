module c3vet::idiomatic_c3_test @test;

import c3vet;
import c3vet::testdata;

fn void idiomatic_c3()
{
	testdata::verify_check(c3vet::IDIOMATIC_C3, "testdata/idiomatic-c3.c3");
}
