module c3vet::self_assign_test @test;

import c3vet;
import c3vet::testdata;

fn void self_assign()
{
	testdata::verify_check(c3vet::SELF_ASSIGN, "testdata/self-assign.c3");
}
