module testdata_const_int_div_to_float;

fn float f(int numerator, int denominator)
{
	float from_literals = 1 / 2; // want "integer division of literals is converted to a floating value"
	float from_expression = (3 / 4) + 0.5; // want "integer division of literals is converted to a floating value"
	float from_float = 1.0 / 2;
	float from_variables = numerator / denominator;
	return from_literals + from_expression + from_float + from_variables;
}

fn float return_quotient()
{
	return 5 / 2; // want "integer division of literals is converted to a floating value"
}

fn int compute(int n) => n;

fn void call_argument_is_its_own_context()
{
	// The division is an int argument to `compute`, independent of the
	// outer cast -- it is not being converted to float.
	double x = (double)compute(5 / 2);
}
