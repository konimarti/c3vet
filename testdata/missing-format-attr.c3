module testdata_missing_format_attr;

import std::io;

fn void local_fmt(String fmt, args...) @format(0)
{
	io::printfn(fmt, ...args);
}

fn void bad_wrapper(String fmt, args...) // want "forwards its format string to 'local_fmt' (which has @format(0)) but has no @format itself"
{
	local_fmt(fmt, ...args);
}

fn void good_wrapper(String fmt, args...) @format(0)
{
	local_fmt(fmt, ...args);
}

fn void bad_stdlib_wrapper(String fmt, args...) // want "forwards its format string to 'printfn' (which has @format(0)) but has no @format itself"
{
	io::printfn(fmt, ...args);
}

fn void not_varargs(String fmt, int x)
{
	local_fmt(fmt, x);
}

fn void literal_forward(String fmt, args...)
{
	local_fmt("fixed", ...args);
}

// the advised index is the wrapper's own, not the callee's
fn void bad_level_wrapper(int level, String fmt, args...) // want "add @format(1) to this function too"
{
	local_fmt(fmt, ...args);
}

fn void good_level_wrapper(int level, String fmt, args...) @format(1)
{
	local_fmt(fmt, ...args);
}

struct Logger
{
	int level;
}

fn void Logger.bad_log(&self, String fmt, args...) // want "add @format(1) to this function too"
{
	local_fmt(fmt, ...args);
}

fn void Logger.good_log(&self, String fmt, args...) @format(1)
{
	local_fmt(fmt, ...args);
}
