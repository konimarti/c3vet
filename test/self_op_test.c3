module c3vet::self_op_test @test;

import c3vet;
import c3vet::testdata;

fn void self_op()
{
	testdata::verify_check(c3vet::SELF_OP, "testdata/self-op.c3");
}
