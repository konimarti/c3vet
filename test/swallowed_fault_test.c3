module c3vet::swallowed_fault_test @test;
import c3vet;
import c3vet::testdata;
fn void swallowed_fault()
{
	testdata::verify_check(c3vet::SWALLOWED_FAULT,
		"testdata/swallowed-fault.c3");
}
