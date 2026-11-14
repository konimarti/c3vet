module c3vet::contract_tautology_test @test;

import c3vet::testdata;
import c3vet;

fn void contract_tautology()
{
	testdata::verify_check(c3vet::CONTRACT_TAUTOLOGY, "testdata/contract-tautology.c3");
}
