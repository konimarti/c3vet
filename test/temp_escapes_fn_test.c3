module c3vet::temp_escapes_fn_test @test;

import c3vet;
import c3vet::testdata;

fn void test_temp_escapes_fn()
{
	testdata::verify_check(c3vet::TEMP_ESCAPES_FN,
		"testdata/temp-escapes-fn.c3");
}
