module c3vet::redundant_module_scope_test @test;

import c3vet;
import c3vet::project_check_support;

fn void redundant_module_scope()
{
	c3vet::project_check_support::verify_project_check(
		c3vet::REDUNDANT_MODULE_SCOPE, "testdata/redundant-module-scope.c3", 3);
}
