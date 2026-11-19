module c3vet::redundant_mem_free_test @test;

import c3vet;
import c3vet::testdata;

fn void redundant_mem_free()
{
	testdata::verify_check(c3vet::REDUNDANT_MEM_FREE,
		"testdata/redundant-mem-free.c3");
}
