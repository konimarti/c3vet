module c3vet::const_int_div_to_float_test @test;

import c3vet;
import c3vet::testdata;

fn void const_int_div_to_float()
{
	testdata::verify_check(c3vet::CONST_INT_DIV_TO_FLOAT, "testdata/const-int-div-to-float.c3");
}
