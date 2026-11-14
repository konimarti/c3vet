module testdata_dup_branch;

fn void repeated_condition(bool first, bool second)
{
	if (first) { first_action; }
	else if (first) { second_action; } // want "duplicate condition in if/else-if chain"
}

fn void repeated_body(bool first, bool second)
{
	if (first) { action; }
	else if (second) { action; } // want "duplicate block body in if/else-if chain"
}

fn void repeated_else_body(bool first)
{
	if (first) { action; }
	else { action; } // want "duplicate block body in if/else-if chain"
}

fn void different_branches(bool first, bool second)
{
	if (first) { first_action; }
	else if (second) { second_action; }
}
