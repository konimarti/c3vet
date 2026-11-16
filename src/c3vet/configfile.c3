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

<* Looks in `dir` for `.c3vet` or `project.json`'s "c3vet" key, and applies whichever is found (first one wins) to `cfg`. *>
fn void load_config_file(Config* cfg, String dir)
{
	Object* obj = load_c3vet_file(dir);
	if (!obj) obj = load_project_json_key(dir);
	if (!obj) return;
	apply_config_object(cfg, obj);
}

fn Object* load_c3vet_file(String dir) @local
{
	String p = string::tformat("%s/.c3vet", dir);
	char[]? bytes = file::load(tmem, p);
	if (catch bytes) return null;
	Object*? root = json::tparse((String)bytes);
	if (catch root) return null;
	return root;
}

fn Object* load_project_json_key(String dir) @local
{
	String p = string::tformat("%s/project.json", dir);
	char[]? bytes = file::load(tmem, p);
	if (catch bytes) return null;
	Object*? root = json::tparse((String)bytes);
	if (catch root) return null;
	Object*? c3vet_obj = root.get("c3vet");
	if (catch c3vet_obj) return null;
	return c3vet_obj;
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
