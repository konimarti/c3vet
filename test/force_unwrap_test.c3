module c3vet::force_unwrap_test @test;
import c3vet;
import c3vet::testdata;
fn void force_unwrap()
{
	testdata::verify_check(c3vet::FORCE_UNWRAP, "testdata/force-unwrap.c3");
}
