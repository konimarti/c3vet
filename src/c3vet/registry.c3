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
	SELF_ASSIGN,
	SELF_COMPARE,
	SELF_OP,
	DUP_BRANCH,
	CONST_COND,
	CONST_INT_DIV_TO_FLOAT,
	CONST_NARROWING_OVERFLOW,
	EMPTY_BODY,
	EMPTY_LOOP_BODY,
	LOOP_NO_ADVANCE,
	UNUSED_LABEL,
	TEMP_ESCAPES_FN,
	TEMP_ESCAPES_POOL,
	TEMP_ESCAPES_STRUCT,
	TEMP_WRONG_FREE,
	TEMP_TO_GLOBAL,
	SWALLOWED_FAULT,
	SILENCED_FAULT,
	UNUSED_CATCH_BINDING,
	UNUSED_TRY_BINDING,
	FORCE_UNWRAP,
	FLOAT_EQUAL,
	COND_NOT_BOOL,
	DEFER_IN_LOOP,
	MISSING_FORMAT_ATTR,
	UNUSED_IMPORT,
	UNUSED_PRIVATE_DECL,
	CONTRACT_VOID_RETURN,
	CONTRACT_TAUTOLOGY,
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
