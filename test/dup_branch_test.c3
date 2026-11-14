module c3vet::dup_branch_test @test;

import c3vet;
import c3vet::testdata;

fn void dup_branch()
{
	testdata::verify_check(c3vet::DUP_BRANCH, "testdata/dup-branch.c3");
}
