module c3vet::unused_import_test @test;

import c3vet;
import c3vet::project_check_support;

fn void unused_import()
{
	c3vet::project_check_support::verify_project_check(c3vet::UNUSED_IMPORT,
		"testdata/unused-import.c3", 1);
}
