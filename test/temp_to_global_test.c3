module c3vet::temp_to_global_test @test;

import c3vet;
import c3vet::testdata;

fn void test_temp_to_global()
{
	testdata::verify_check(c3vet::TEMP_TO_GLOBAL, "testdata/temp-to-global.c3");
	// No sibling c3c checkout on this machine (true in CI): measure_fp_check
	// returns 0 unconditionally, so there is nothing to assert here -- see
	// its own doc comment.
	if (!testdata::has_checkout()) return;

	sz fps = testdata::measure_fp_check(c3vet::TEMP_TO_GLOBAL);
	// 1 expected: c3c's own test/unit/regression/panic_messages.c3 assigns
	// `string::tformat(...)` / `.tcopy()` to a global `String`, a real hit
	// of the pattern this check exists to catch, not a false positive.
	assert(fps == 1, "expected 1 known hit for temp-to-global");
}
