module testdata_force_unwrap;

fn int? maybe() => 1;

fn int production()
{
	return maybe()!!; // want "force unwrap may panic"
}

fn void main()
{
	int value = maybe()!!;
}

fn void test_force_unwrap() @test
{
	int value = maybe()!!;
}
