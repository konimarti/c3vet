module c3vet::mem_copy_slice_to_array_test @test;

import c3vet;
import c3vet::testdata;

fn void mem_copy_slice_to_array()
{
	testdata::verify_check(c3vet::MEM_COPY_SLICE_TO_ARRAY,
		"testdata/mem-copy-slice-to-array.c3");
}
