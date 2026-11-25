module testdata_dup_branch;

fn void repeated_condition(bool first, bool second)
{
	if (first)
	{
		first_action;
	}
	else if (first) // want "duplicate condition in if/else-if chain"
	{
		second_action;
	}
}

fn void repeated_body(bool first, bool second)
{
	if (first)
	{
		action;
	}
	else if (second) // want "duplicate block body in if/else-if chain"
	{
		action;
	}
}

fn void repeated_else_body(bool first)
{
	if (first)
	{
		action;
	}
	else
	{ // want "the else repeats an earlier branch"
		action;
	}
}

fn void different_branches(bool first, bool second)
{
	if (first)
	{
		first_action;
	}
	else if (second)
	{
		second_action;
	}
}
