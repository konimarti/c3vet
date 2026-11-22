module c3vet::temp_escapes_struct_test @test;

import c3vet;
import c3vet::testdata;

fn void test_temp_escapes_struct()
{
	testdata::verify_check(c3vet::TEMP_ESCAPES_STRUCT,
		"testdata/temp-escapes-struct.c3");
}
