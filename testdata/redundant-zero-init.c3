module testdata_redundant_zero_init;

fn void zero_init_rule()
{
	char[8] encoded = {};     // want "redundant"
	char[8] decoded;          // no diagnostic expected
	int[] nums = { 1, 2 };    // no diagnostic expected
}
