<*
 Configuration: which checks run, and over what.

 Resolution order, loosest to strongest: each check's `default_on`, then the
 config file, then the command line. This is the per-check granularity c3c
 cannot offer -- it has 8 coarse warning knobs, each only no/yes/error.
*>
module c3vet;

import std::collections::list;
import std::io;

struct Config
{
	<* Names forced on, from --enable. *>
	List{String} enabled;
	<* Names forced off, from --disable. *>
	List{String} disabled;
	<* Run every check, from --enable-all. *>
	bool         enable_all;
	<* Ignore every suppression comment, for an audit run. *>
	bool         no_suppress;
	<* Report findings for dependencies and the stdlib too. Diagnostic use. *>
	bool         include_deps;
}

fn void Config.init(&self, Allocator a)
{
	self.enabled.init(a);
	self.disabled.init(a);
}

fn void Config.free(&self)
{
	self.enabled.free();
	self.disabled.free();
}

<*
 Whether `c` runs, given its default and any overrides.

 --disable always wins over --enable and --enable-all, so a broad enable plus a narrow
 --disable behaves the way a user expects.
*>
fn bool Config.runs(&self, Check c)
{
	foreach (n : self.disabled) if (n == c.name) return false;
	if (self.enable_all) return true;
	foreach (n : self.enabled) if (n == c.name) return true;
	return c.default_on;
}

<* The subset of `all` that this configuration runs. Result in temp memory. *>
fn Check[] Config.select(&self, Check[] all)
{
	List{Check} out;
	out.tinit();
	foreach (c : all) if (self.runs(c)) out.push(c);
	return out.to_tarray();
}
