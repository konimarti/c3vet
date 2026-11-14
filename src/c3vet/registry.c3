<*
 The check registry.

 ORCHESTRATOR-OWNED. This is the one file where three lanes would otherwise
 conflict on every commit, so lanes do not edit it: report your check's
 `Check` literal in your completion note and the orchestrator lands it.
 See docs/WORKPLAN.md rule 3.
*>
module c3vet;

<* Every check that exists, in a stable order. *>
const Check[] ALL_CHECKS = {
	PARSE,
	STUB_EMPTY_BLOCK,
};

<*
 Index of the check named `name` in ALL_CHECKS, or -1.
 @return "the index, or -1 when no check has that name"
*>
fn sz find_check(String name)
{
	foreach (i, c : ALL_CHECKS) if (c.name == name) return (sz)i;
	return -1;
}
