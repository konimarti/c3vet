module c3vet::unused_catch_binding_test @test;
import c3vet;
import c3vet::testdata;
fn void unused_catch_binding()
{
	testdata::verify_check(c3vet::UNUSED_CATCH_BINDING,
		"testdata/unused-catch-binding.c3");
}
