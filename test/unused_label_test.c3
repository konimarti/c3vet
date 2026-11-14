module c3vet::unused_label_test @test;

import c3vet::testdata;
import c3vet;

fn void unused_label()
{
	testdata::verify_check(c3vet::UNUSED_LABEL, "testdata/unused-label.c3");
}
