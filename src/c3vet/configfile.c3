<*
 Project-level configuration, loaded once per run.

 Config lives in project.json under a `c3vet` key, or in a `.c3vet` file in
 the project root; the same shape either way: `enable`/`disable` string
 arrays and a `no-suppress` bool. `.c3vet` wins if both exist.

 Resolution order: each check's default_on, then the config file, then the
 command line, so an explicit `--enable=x` beats a file that disabled `x`,
 and vice versa.
*>
module c3vet;

import std::io;
import std::io::file;
import std::io::path;
import std::encoding::json;
import std::collections::object;
import std::collections::list;

<*
 Looks in `dir` for `.c3vet` or `project.json`'s "c3vet" key, and applies
 whichever is found (first one wins) to `cfg`.

 Both candidates' parsed JSON stay temp-allocated and are applied inline,
 right here, rather than returned from a helper -- a `tparse` result is only
 valid within the temp scope that produced it, and `cfg.enabled`/`disabled`
 only ever keep the small persistent copies `apply_name_array` makes of it.
*>
fn void load_config_file(Config* cfg, String dir)
{
	String c3vet_path = string::tformat("%s/.c3vet", dir);
	char[]? c3vet_bytes = file::load(tmem, c3vet_path);
	if (try c3vet_bytes)
	{
		Object*? root = json::tparse((String)c3vet_bytes);
		if (try root)
		{
			apply_config_object(cfg, root);
			return;
		}
	}

	String project_path = string::tformat("%s/project.json", dir);
	char[]? project_bytes = file::load(tmem, project_path);
	if (catch project_bytes) return;
	Object*? project_root = json::tparse((String)project_bytes);
	if (catch project_root) return;
	Object*? c3vet_obj = project_root.get("c3vet");
	if (catch c3vet_obj) return;
	apply_config_object(cfg, c3vet_obj);
}

fn void apply_config_object(Config* cfg, Object* obj) @local
{
	apply_name_array(&cfg.enabled, &cfg.disabled, obj, "enable");
	apply_name_array(&cfg.disabled, &cfg.enabled, obj, "disable");
	bool? no_suppress = obj.get_bool("no-suppress");
	if (try no_suppress) cfg.no_suppress = no_suppress;
}

fn void apply_name_array(List{String}* out, List{String}* opposite, Object* obj, String key) @local
{
	Object*? arr = obj.get(key);
	if (catch arr) return;
	for (sz i = 0; i < arr.len(); i++)
	{
		String? s = arr.get_string_at(i);
		if (catch s) continue;
		opposite.remove_item(s);
		out.push(s.copy(out.allocator));
	}
}
