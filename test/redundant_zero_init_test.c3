module c3vet::redundant_zero_init_test @test;

import c3vet;
import c3vet::testdata;

fn void redundant_zero_init()
{
	testdata::verify_check(c3vet::REDUNDANT_ZERO_INIT,
		"testdata/redundant-zero-init.c3");
}
