module c3vet::empty_body_test @test;

import c3vet;
import c3vet::testdata;

fn void empty_body()
{
	testdata::verify_check(c3vet::EMPTY_BODY, "testdata/empty-body.c3");
}
