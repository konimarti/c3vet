module c3vet::catch_default_operator_test @test;

import c3vet;
import c3vet::testdata;

fn void catch_default_operator()
{
	testdata::verify_check(c3vet::CATCH_DEFAULT_OPERATOR,
		"testdata/catch-default-operator.c3");
}
