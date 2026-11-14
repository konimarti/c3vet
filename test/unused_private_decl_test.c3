module c3vet::unused_private_decl_test @test;

import c3vet;
import c3vet::project_check_support;

fn void unused_private_decl()
{
	c3vet::project_check_support::verify_project_check(c3vet::UNUSED_PRIVATE_DECL, "testdata/unused-private-decl.c3", 2);
}
