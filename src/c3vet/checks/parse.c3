<*
 The `parse` check: the file did not parse.

 Reported when a file could not be parsed. Like any other check it can be
 turned off with `--disable=parse`, listed with `--list-checks` and
 suppressed with `// c3vet:ignore[parse]`.
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
