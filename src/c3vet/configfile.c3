<*
 Project-level configuration, loaded once per run.

 docs/DESIGN.md: "Config in project.json under a c3vet key, or .c3vet in the
 project root; CLI flags win." Same shape either way -- `enable`/`disable`
 string arrays and a `no-suppress` bool, the same three things the CLI
 flags cover. `.c3vet` wins if both exist, since a file whose only purpose
 is c3vet's own config is the more specific, more deliberate choice.

 Loaded before `parse_args` so CLI flags can override it: `args.c3`'s
 `add_names` removes a name from the opposite list before adding it, so an
 explicit `--enable=x` always beats a file that disabled `x`, and vice
 versa -- matching config.c3's documented resolution order ("each check's
 default_on, then the config file, then the command line").
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
