module testdata_catch_default_operator;

fn void catch_default_rule(char[]? opt, char[]? other)
{
	char[] out;
	if (catch opt)                 // want "optional else operator"
	{
		out = {};
	}
	else
	{
		out = opt;
	}
	if (catch opt)                 // no diagnostic expected: branches assign different targets
	{
		out = {};
	}
	else
	{
		char[] unused = other;
	}
	out = opt ?? {};               // no diagnostic expected
}
