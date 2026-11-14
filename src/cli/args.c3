<* Command-line parsing. *>
module c3vet::cli;

import c3vet;
import std::collections::list;
import std::io;

struct Options
{
	List{String} targets;
	bool         list_checks;
	bool         help;
	bool         version;
	bool         no_suppress;
	<* Set when an argument was rejected; `error_msg` says why. *>
	bool         bad;
	String       error_msg;
}

fn void Options.init(&self, Allocator a) => self.targets.init(a);
fn void Options.free(&self) => self.targets.free();

const String USAGE = `usage: c3vet [options] [path...]

Reports suspicious but legal C3: code that compiles cleanly and is almost
certainly not what you meant. What c3c already diagnoses, c3vet stays quiet
about.

With no path, the current project's sources are used.

options:
  --list-checks        list every check and whether it runs by default
  --enable=a,b         run these checks as well
  --disable=a,b        do not run these checks
  --no-suppress        ignore every // c3vet:ignore comment (audit run)
  -h, --help           this text
  -V, --version        version

exit: 0 clean, 1 findings, 2 tool error`;

fn Options parse_args(Allocator a, String[] argv, Config* cfg)
{
	Options o;
	o.init(a);
	foreach (arg : argv)
	{
		if (arg == "-h" || arg == "--help") { o.help = true; continue; }
		if (arg == "-V" || arg == "--version") { o.version = true; continue; }
		if (arg == "--list-checks") { o.list_checks = true; continue; }
		if (arg == "--no-suppress") { o.no_suppress = true; cfg.no_suppress = true; continue; }
		if (arg.starts_with("--enable=")) { add_names(&cfg.enabled, arg["--enable=".len..]); continue; }
		if (arg.starts_with("--disable=")) { add_names(&cfg.disabled, arg["--disable=".len..]); continue; }
		if (arg.starts_with("-"))
		{
			o.bad = true;
			o.error_msg = string::format(a, "unknown option '%s'", arg);
			return o;
		}
		o.targets.push(arg.copy(a));
	}
	return o;
}

<* Split a comma-separated list onto `out`, ignoring empty entries. *>
fn void add_names(List{String}* out, String csv) @local
{
	usz from = 0;
	while (from <= csv.len)
	{
		usz end = from;
		while (end < csv.len && csv[end] != ',') end++;
		if (end > from)
		{
			String name = csv[from..end - 1].trim();
			if (name.len) out.push(name.copy(out.allocator));
		}
		if (end >= csv.len) break;
		from = end + 1;
	}
}
