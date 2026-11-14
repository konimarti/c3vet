<*
 The c3vet command.

 Exit codes: 0 clean, 1 findings, 2 tool error. Findings go to stdout and
 tool errors to stderr, so `c3vet | wc -l` is meaningful in CI.
*>
module c3vet::cli;

import c3vet;
import c3::parser;
import std::collections::list;
import std::io;
import std::sort;

const String VERSION = "0.1.0";

const int EXIT_CLEAN    = 0;
const int EXIT_FINDINGS = 1;
const int EXIT_ERROR    = 2;

fn int main(String[] argv)
{
	Config cfg;
	cfg.init(mem);
	defer cfg.free();

	Options o = parse_args(mem, argv[1..], &cfg);
	defer o.free();

	if (o.bad)
	{
		io::eprintfn("c3vet: %s", o.error_msg);
		io::eprintn(USAGE);
		return EXIT_ERROR;
	}
	if (o.help) { io::printn(USAGE); return EXIT_CLEAN; }
	if (o.version) { io::printfn("c3vet %s", VERSION); return EXIT_CLEAN; }
	if (o.list_checks) { list_checks(); return EXIT_CLEAN; }

	// Reject names that match no check, rather than silently doing nothing.
	foreach (n : cfg.enabled)
	{
		if (c3vet::find_check(n) < 0)
		{
			io::eprintfn("c3vet: no such check '%s'; try --list-checks", n);
			return EXIT_ERROR;
		}
	}
	foreach (n : cfg.disabled)
	{
		if (c3vet::find_check(n) < 0)
		{
			io::eprintfn("c3vet: no such check '%s'; try --list-checks", n);
			return EXIT_ERROR;
		}
	}

	List{String} files;
	files.init(mem);
	defer files.free();

	if (!o.targets.len())
	{
		// No path given: the current project's sources.
		if (!collect(&files, "src"))
		{
			io::eprintn("c3vet: no 'src' directory here; pass a path");
			return EXIT_ERROR;
		}
	}
	else
	{
		foreach (t : o.targets)
		{
			if (!collect(&files, t))
			{
				io::eprintfn("c3vet: cannot read '%s'", t);
				return EXIT_ERROR;
			}
		}
	}

	Check[] enabled = cfg.select(c3vet::ALL_CHECKS);

	DiagnosticList diags;
	diags.init(mem);
	defer diags.free();

	Ctx ctx = { .config = &cfg, .out = &diags };
	ctx.reported.init(mem);
	defer ctx.reported.free();

	foreach (f : files)
	{
		if (!vet_file(&ctx, f, enabled))
		{
			io::eprintfn("c3vet: cannot read '%s'", f);
			return EXIT_ERROR;
		}
	}

	sort::quicksort(diags.array_view(), &c3vet::cmp_diagnostic);
	foreach (d : diags) io::printn(d.to_string(tmem));

	if (diags.len() > 0)
	{
		io::eprintfn("c3vet: %d finding(s) in %d file(s)%s",
			diags.len(), files.len(), suppressed_note(&ctx));
		return EXIT_FINDINGS;
	}
	// Report suppressions even on a clean run: a suppression you have
	// forgotten about hides a real finding, so it must never be invisible.
	if (ctx.suppressed)
	{
		io::eprintfn("c3vet: no findings in %d file(s), %d suppressed",
			files.len(), ctx.suppressed);
	}
	return EXIT_CLEAN;
}

<*
 A suppression you have forgotten about is a bug, so the count is always
 reported rather than hidden.
*>
fn String suppressed_note(Ctx* ctx) @local
{
	if (!ctx.suppressed) return "";
	return string::tformat(", %d suppressed", ctx.suppressed);
}

fn bool vet_file(Ctx* ctx, String path, Check[] enabled) @local
{
	char[]? bytes = file::load(tmem, path);
	if (catch bytes) return false;

	Unit u;
	u.path = path;
	u.src = (String)bytes;
	u.parsed = parser::parse(tmem, u.src);
	u.suppress.init(tmem);
	if (!ctx.config.no_suppress) u.suppress.collect(u.toks());

	// Parse failures are findings too, reported under the "parse" name.
	c3vet::collect_parse_errors(ctx.out, path, &u.parsed);
	c3vet::run_checks(ctx, &u, enabled);
	return true;
}

fn void list_checks() @local
{
	foreach (c : c3vet::ALL_CHECKS)
	{
		io::printfn("%-20s %-8s %s  %s",
			c.name, tier_name(c.tier), c.default_on ? "on " : "off", c.doc);
	}
}

fn String tier_name(Tier t) @local
{
	switch (t)
	{
		case SYNTAX: return "syntax";
		case LOCAL: return "local";
		case PROJECT: return "project";
	}
}
