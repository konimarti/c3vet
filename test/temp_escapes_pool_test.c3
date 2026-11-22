module c3vet::temp_escapes_pool_test @test;

import c3vet;
import c3vet::testdata;

fn void test_temp_escapes_pool()
{
	testdata::verify_check(c3vet::TEMP_ESCAPES_POOL,
		"testdata/temp-escapes-pool.c3");
	sz fps = testdata::measure_fp_check(c3vet::TEMP_ESCAPES_POOL);
	assert(fps >= 0, "FP check completed");
}
