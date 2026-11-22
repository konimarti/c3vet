<*
 Target resolution: which files c3vet reads.

 Dependencies, build output and dot-directories are never walked, so findings
 are reported only for the project's own sources.
*>
module c3vet::cli;

import std::collections::list;
import std::io;
import std::io::path;

fn bool is_source(String p)
	=> p.ends_with(".c3") || p.ends_with(".c3i") || p.ends_with(".c3t");

<* Directories that are never project sources. *>
fn bool skipped_dir(String name) => name.starts_with(".") || name == "build"
	|| name == "lib" || name == "out";

<*
 Add every source file under `target` to `out`.

 `target` may be a file or a directory; directories are walked recursively.
 @return "false when the target could not be read"
*>
fn bool collect(List{String}* out, String target)
{
	if (!path::exists(path::tnew(target) ?? (Path){}))
	{
		return false;
	}
	if (!file::is_dir(target))
	{
		if (is_source(target)) out.push(target.copy(out.allocator));
		return true;
	}
	return walk_dir(out, target);
}

fn bool walk_dir(List{String}* out, String dir) @local
{
	Path? p = path::tnew(dir);
	if (catch p) return false;
	PathList? entries = path::ls(tmem, p);
	if (catch entries) return false;

	foreach (e : entries)
	{
		String name = e.basename();
		if (name == "." || name == "..") continue;
		String full = string::tformat("%s/%s", dir, name);
		if (file::is_dir(full))
		{
			if (skipped_dir(name)) continue;
			walk_dir(out, full);
			continue;
		}
		if (is_source(name)) out.push(full.copy(out.allocator));
	}
	return true;
}
