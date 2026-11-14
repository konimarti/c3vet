module c3vet::temp_escapes_fn_test @test;

import c3vet::testdata;
import c3vet;

fn void test_temp_escapes_fn()
{
	testdata::verify_check(c3vet::TEMP_ESCAPES_FN, "testdata/temp-escapes-fn.c3");
	sz fps = testdata::measure_fp_check(c3vet::TEMP_ESCAPES_FN);
	assert(fps >= 0, "FP check completed");
}
