module c3vet::temp_to_global_test @test;

import c3vet;
import c3vet::testdata;

fn void test_temp_to_global()
{
	testdata::verify_check(c3vet::TEMP_TO_GLOBAL, "testdata/temp-to-global.c3");
}
