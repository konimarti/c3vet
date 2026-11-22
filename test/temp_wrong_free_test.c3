module c3vet::temp_wrong_free_test @test;

import c3vet;
import c3vet::testdata;

fn void test_temp_wrong_free()
{
	testdata::verify_check(c3vet::TEMP_WRONG_FREE,
		"testdata/temp-wrong-free.c3");
	sz fps = testdata::measure_fp_check(c3vet::TEMP_WRONG_FREE);
	assert(fps == 0, "expected 0 FPs for temp-wrong-free");
}
