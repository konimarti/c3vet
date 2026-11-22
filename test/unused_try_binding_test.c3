module c3vet::unused_try_binding_test @test;
import c3vet;
import c3vet::testdata;
fn void unused_try_binding()
{
	testdata::verify_check(c3vet::UNUSED_TRY_BINDING,
		"testdata/unused-try-binding.c3");
}
