<*
 The `parse` check: the file did not parse.

 A real registered check, not a side channel. That matters because it is the
 loudest thing the tool prints on a broken file, and a finding you cannot
 name is a finding you cannot disable, suppress or count. Being in
 ALL_CHECKS means `--disable=parse`, `--list-checks` and
 `// c3vet:ignore[parse]` all work on it like any other check.
*>
module c3vet;

import c3::parser;

const Check PARSE = {
	.name          = PARSE_CHECK,
	.doc           = "the file did not parse; later checks may be skipped",
	.tier          = Tier.SYNTAX,
	.default_on    = true,
	// The only check that must run precisely when the file is broken.
	.skip_on_error = false,
	.run           = &run_parse,
};

fn void run_parse(Ctx* ctx, Unit* u)
{
	foreach (e : u.parsed.errors)
	{
		ctx.report_at_token(u, e.tok, e.tok, PARSE_CHECK, "%s", e.msg);
	}
	if (u.parsed.lex_failed)
	{
		ctx.report_at_token(u, 0, 0, PARSE_CHECK,
			"invalid byte at offset %d; the rest of the file was not read",
			u.parsed.toks.fail_offset);
	}
}
