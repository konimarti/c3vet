module c3vet::temp_to_global_test @test;

import c3vet::testdata;
import c3vet;

fn void test_temp_to_global()
{
	testdata::verify_check(c3vet::TEMP_TO_GLOBAL, "testdata/temp-to-global.c3");
	sz fps = testdata::measure_fp_check(c3vet::TEMP_TO_GLOBAL);
	assert(fps == 0, "expected 0 FPs for temp-to-global");
}
