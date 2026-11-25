module testdata_force_unwrap;

fn int? maybe() => 1;

fn int? production()
{
	return maybe()!!; // want "force unwrap may panic"
}

fn int cannot_propagate()
{
	return maybe()!!;
}

alias Getter = fn int?();
alias Plain = fn int();

fn void lambda_returns_optional()
{
	Getter g = fn int?() => maybe()!!; // want "force unwrap may panic"
}

fn void? defer_cannot_propagate()
{
	defer
	{
		maybe()!!;
	}
}

fn void? lambda_cannot_propagate()
{
	Plain p = fn int() => maybe()!!;
}

fn void main()
{
	int value = maybe()!!;
}

fn void test_force_unwrap() @test
{
	int value = maybe()!!;
}
