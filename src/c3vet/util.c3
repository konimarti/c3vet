<* Small shared helpers. *>
module c3vet;

import std::collections::list;

<*
 Split a comma-separated list into trimmed, non-empty names.

 Both suppression comments (`// c3vet:ignore[a,b]`) and the command line
 (`--enable=a,b`) take this shape, and hand-rolling the split twice is how
 `[other-check,]` came to panic on an out-of-range slice. One helper, one
 set of edge cases: empty input, leading/trailing/doubled commas, whitespace.

 @param a : "allocator for the result slice; the names are not copied"
 @return "the names, in order; empty when there are none"
*>
fn String[] split_names(Allocator a, String csv)
{
	List{String} out;
	out.init(a);
	usz from = 0;
	while (from < csv.len)
	{
		usz end = from;
		while (end < csv.len && csv[end] != ',') end++;
		if (end > from)
		{
			String name = csv[from..end - 1].trim();
			if (name.len) out.push(name);
		}
		from = end + 1;
	}
	return out.array_view();
}
