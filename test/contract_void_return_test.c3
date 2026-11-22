module c3vet::contract_void_return_test @test;

import c3vet;
import c3vet::testdata;

fn void contract_void_return()
{
	testdata::verify_check(c3vet::CONTRACT_VOID_RETURN,
		"testdata/contract-void-return.c3");
}
