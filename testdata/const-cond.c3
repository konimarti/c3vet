module testdata_const_cond;

const bool ALWAYS = false;

fn void constant_conditions(bool flag)
{
	if (1 == 2) { never; } // want "condition is determined by literals alone"
	while (false) { never; } // want "condition is determined by literals alone"
	if (flag) { work; }
	if (ALWAYS) { work; }
	if (1 + 2) { work; }
	while (true) { if (flag) break; } // no annotation: loop-forever-break-inside is idiomatic, not a toggle
}
