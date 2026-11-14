<*
 Project-wide declaration table.

 Indexes the WIDER scope -- project sources plus lib/*.c3l dependencies plus
 the standard library, declarations only, function bodies skipped -- and
 answers questions about declarations: "does io::printfn carry @format(n)?",
 "what does std::math export?". `Ctx.report` enforces the narrower reported
 scope, so a stale or stdlib-only entry here can never surface as a
 diagnostic -- see docs/DESIGN.md section 5.

 Only `missing-format-attr` needs the standard library indexed. The other T3
 consumers (`unused-import`, `unused-private-decl`) only need project-local
 declarations, so a run where the standard library cannot be located still
 produces a correct (if more conservative) table -- see `find_stdlib_root`.

 Indexing reuses `c3::parser`, same as a reported-scope file, rather than a
 second hand-rolled scanner. The real standard library uses some syntax this
 parser does not yet cover (confirmed empirically: `lib/std/io/io.c3` hits an
 unparsed construct partway through and recovers via error nodes), so a file
 like that is only indexed up to its first unparsed declaration. This can
 never cause a false positive -- a missing entry just means less is known,
 which is exactly the conservative degradation `unused-import`/
 `missing-format-attr` are specified to prefer (`docs/CHECKS.md`).
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import std::core::dstring;
import std::core::string;
import std::io;
import std::io::path;
import std::os::env;

enum DeclVis : char
{
	PUBLIC,
	PRIVATE,
	LOCAL,
}

<* One indexed declaration: its module, name, kind and visibility. *>
struct DeclInfo
{
	String   mod;
	String   name;
	NodeKind kind;
	DeclVis  vis;
	<* 0-based parameter index from `@format(n)`; -1 when absent. *>
	int      format_param;
}

struct DeclTable
{
	List{DeclInfo} decls;
}

fn void DeclTable.init(&self, Allocator a)
{
	self.decls.init(a);
}

<* First declaration named `name`. `mod`, if non-empty, restricts the search to that module. *>
fn DeclInfo* DeclTable.find(&self, String mod, String name)
{
	foreach (&d : self.decls)
	{
		if (d.name != name) continue;
		if (mod.len && d.mod != mod) continue;
		return d;
	}
	return null;
}

<*
 The `@format(n)` parameter index of the public declaration named `name`
 in module `mod`; -1 if none carries one.

 `mod`, if non-empty, is the qualifier as written at the call site
 (`io::printfn(...)` -> `"io"`) -- which C3 always spells as the LAST
 segment of whatever module was imported, never the full path (confirmed
 empirically: `import std::io;` makes `io::printfn` the call syntax, not
 `std::io::printfn`). Matched against each declaration's own full module
 path by its last segment, via `module_qualifier_matches`, not by exact
 equality. `mod` empty means the call was unqualified, so the name must be
 unambiguous across every indexed module to trust it: two unrelated public
 functions sharing a name (`log`, `write`, `debug` are common across
 libraries) previously matched whichever happened to come first in the
 table, which could silently attribute the wrong function's `@format` to
 an unrelated same-named callee. Either way, ambiguous is answered as "no
 `@format` found" (-1), not a guess, same as everywhere else this tool
 prefers a false negative over a false positive.
*>
fn int DeclTable.format_param_of(&self, String mod, String name)
{
	if (mod.len)
	{
		int result = -1;
		bool found = false;
		foreach (&d : self.decls)
		{
			if (d.vis != DeclVis.PUBLIC || d.name != name) continue;
			if (!module_qualifier_matches(d.mod, mod)) continue;
			if (found) return -1;
			found = true;
			result = d.format_param;
		}
		return result;
	}
	int result = -1;
	bool found = false;
	foreach (&d : self.decls)
	{
		if (d.vis != DeclVis.PUBLIC || d.name != name) continue;
		if (found) return -1;
		found = true;
		result = d.format_param;
	}
	return result;
}

<*
 Names of every PUBLIC declaration in `mod_prefix` or one of its submodules
 (`std::net` matches `std::net::tcp`, per C3's own import semantics).
*>
fn String[] DeclTable.exported_names(&self, Allocator a, String mod_prefix)
{
	List{String} out;
	out.init(a);
	foreach (&d : self.decls)
	{
		if (d.vis != DeclVis.PUBLIC) continue;
		if (!module_matches(d.mod, mod_prefix)) continue;
		out.push(d.name);
	}
	return out.array_view();
}

<* Every declaration in exactly `mod` (any visibility), for `unused-private-decl` to scan. *>
fn DeclInfo[] DeclTable.decls_in(&self, Allocator a, String mod)
{
	List{DeclInfo} out;
	out.init(a);
	foreach (&d : self.decls)
	{
		if (d.mod == mod) out.push(*d);
	}
	return out.array_view();
}

fn bool module_matches(String mod, String prefix) @local
{
	if (mod == prefix) return true;
	return mod.len > prefix.len + 2
		&& mod[:prefix.len] == prefix
		&& mod[prefix.len..prefix.len + 1] == "::";
}

<* True when `qualifier` is `mod` itself, or `mod`'s last `::`-separated segment. *>
fn bool module_qualifier_matches(String mod, String qualifier) @local
{
	if (mod == qualifier) return true;
	if (!mod.ends_with(qualifier)) return false;
	usz prefix_len = mod.len - qualifier.len;
	return prefix_len >= 2 && mod[prefix_len - 1] == ':' && mod[prefix_len - 2] == ':';
}

<*
 Build the table from a set of roots (files or directories; directories are
 walked recursively, unlike the reported-scope walk in `cli::collect`, this
 one does not skip `lib`). Every declaration name and module path is copied
 into `a`, so the table outlives the per-file transient parse that produced
 it.
*>
fn void build_table(DeclTable* t, String[] roots, Allocator a)
{
	t.init(a);
	List{String} files;
	files.tinit();
	foreach (r : roots) collect_indexed(&files, r);
	foreach (f : files) index_file(t, f, a);
}

<*
 Adds declarations from `stdlib_root` to an already-built table, restricted
 to the modules actually imported -- directly, or as a submodule of an
 import -- by any file in `project_files`. Not the whole real standard
 library: measured indexing every stdlib file regardless of relevance at
 over 100ms by itself, for a one-file project that uses a small fraction
 of it. `module_matches` is the same submodule-prefix rule `exported_names`
 already uses ("import std::net" is used by "std::net::tcp" too), so a
 stdlib file is included under exactly the same rule a usage check would
 use to decide the import itself is used.

 Each stdlib file is lexed (`peek_module_name`) to learn its module before
 deciding whether the much more expensive full parse-and-index
 (`index_file`) is worth doing on it -- lexing alone is roughly half of a
 full file's indexing cost (measured ~32 MB/s lexing vs ~15 MB/s full
 parse over the real corpus), so skipping full indexing for an irrelevant
 file still leaves its lex cost paid, but a project's own imports are
 almost always a small fraction of the standard library, so the saved
 parses dominate.
*>
fn void add_stdlib_declarations(DeclTable* t, String stdlib_root, String[] project_files, Allocator a)
{
	if (!stdlib_root.len) return;

	List{String} needed;
	needed.tinit();
	foreach (f : project_files) collect_imports_one(f, &needed);
	if (!needed.len()) return;

	List{String} stdlib_files;
	stdlib_files.tinit();
	collect_indexed(&stdlib_files, stdlib_root);

	foreach (f : stdlib_files)
	{
		String mod = peek_module_name(f);
		if (!mod.len) continue;
		bool relevant = false;
		foreach (n : needed)
		{
			if (module_matches(mod, n)) { relevant = true; break; }
		}
		if (relevant) index_file(t, f, a);
	}
}

<* Every `IMPORT`'s module path in one file, appended to `out` (not deduplicated -- a handful of repeats costs nothing next to the parse itself). *>
fn void collect_imports_one(String path_, List{String}* out) @local
{
	@pool()
	{
		char[]? bytes = file::load(tmem, path_);
		if (catch bytes) return;
		ParseResult r = parser::parse(tmem, (String)bytes);
		foreach (c : r.ast.children(r.ast.root))
		{
			if (r.ast.kind(c) != NodeKind.IMPORT) continue;
			foreach (child : r.ast.children(c))
			{
				if (r.ast.kind(child) != NodeKind.PATH) continue;
				out.push(path_text(&r.toks, r.ast.node(child), out.allocator));
			}
		}
	};
}

<* The module path of one file, lexed only -- not fully parsed -- for the cheapest possible answer to "is this file relevant at all". *>
fn String peek_module_name(String path_) @local
{
	char[]? bytes = file::load(tmem, path_);
	if (catch bytes) return "";
	TokenList toks;
	toks.init(tmem);
	toks.lex((String)bytes);
	for (uint i = 0; i < toks.len(); i++)
	{
		if (toks.type_at(i) != MODULE) continue;
		DString s;
		s.tinit();
		for (uint j = i + 1; j < toks.len(); j++)
		{
			TokenType t = toks.type_at(j);
			if (t != IDENT && t != SCOPE) break;
			s.append(toks.text_at(j));
		}
		return s.str_view();
	}
	return "";
}

fn bool collect_indexed(List{String}* out, String target) @local
{
	Path? p = path::tnew(target);
	if (catch p) return false;
	if (!path::exists(p)) return false;
	if (!file::is_dir(target))
	{
		if (is_indexable(target)) out.push(target);
		return true;
	}
	return walk_dir_indexed(out, target);
}

fn bool walk_dir_indexed(List{String}* out, String dir) @local
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
			if (name.starts_with(".") || name == "build" || name == "out") continue;
			walk_dir_indexed(out, full);
			continue;
		}
		if (is_indexable(name)) out.push(full);
	}
	return true;
}

fn bool is_indexable(String p) @local => p.ends_with(".c3") || p.ends_with(".c3i");

<*
 Index one file: parse it transiently, walk its top-level declarations
 tracking the current module (a file may switch module mid-file), copy the
 small bits of metadata that need to outlive the parse into `a`.
*>
fn void index_file(DeclTable* t, String path_, Allocator a) @local
{
	@pool()
	{
		char[]? bytes = file::load(tmem, path_);
		if (catch bytes) return;
		ParseResult r = parser::parse(tmem, strip_bodies((String)bytes, tmem));
		index_top_level(t, &r.ast, &r.toks, r.ast.root, a);
	};
}

<*
 Blank every top-level `{ ... }` body (recursively -- nested braces inside
 stay blanked too) before handing the file to `parser::parse`.

 Declaration-only indexing does not need bodies, and the full parser is not
 required to fully parse arbitrary real-world body syntax: verified
 empirically that `lib/std/io/io.c3` contains a body construct (a compile-time
 `$typeof(...)`-typed local declaration) this parser's statement grammar does
 not resynchronize cleanly from, which swallows every later top-level
 declaration in the file. Blanking bodies first sidesteps that case entirely
 -- `printfn`/`fprintf`/`printf` (37 top-level decls, 0 errors) are indexed
 where parsing the raw file found only 5 before the first failure.

 Brace matching is done over tokens from the real lexer, not raw bytes, so a
 `"{"` inside a string or comment is never mistaken for a body boundary.
*>
fn String strip_bodies(String src, Allocator a) @local
{
	TokenList toks;
	toks.init(tmem);
	toks.lex(src);

	String buf = src.copy(a);
	int depth = 0;
	uint open_offset = 0;
	uint n = (uint)toks.len();
	for (uint i = 0; i < n; i++)
	{
		lexer::Token t = toks.tok(i);
		if (t.type == TokenType.LBRACE)
		{
			if (depth == 0) open_offset = (uint)(t.offset + t.len);
			depth++;
		}
		else if (t.type == TokenType.RBRACE)
		{
			depth--;
			if (depth == 0)
			{
				uint close_offset = (uint)t.offset;
				for (uint b = open_offset; b < close_offset; b++)
				{
					if (buf[b] != '\n') buf[b] = ' ';
				}
			}
		}
	}
	return buf;
}

fn void index_top_level(DeclTable* t, Ast* ast, TokenList* toks, NodeId root, Allocator a) @local
{
	if (root == parser::NONE) return;
	String cur_mod = "";
	foreach (c : ast.children(root))
	{
		Node* n = ast.node(c);
		if (n.kind == NodeKind.MODULE)
		{
			NodeId[] mkids = ast.children(c);
			if (mkids.len && mkids[0] != parser::NONE)
			{
				cur_mod = path_text(toks, ast.node(mkids[0]), a);
			}
			continue;
		}
		if (n.kind == NodeKind.IMPORT || n.kind == NodeKind.ERROR_DECL) continue;
		if (!n.kind.is_decl()) continue;
		index_decl(t, ast, toks, c, cur_mod, a);
	}
}

fn void index_decl(DeclTable* t, Ast* ast, TokenList* toks, NodeId id, String mod, Allocator a) @local
{
	Node* n = ast.node(id);
	String name = toks.text_at(n.tok);
	if (!name.len || name[0] == '@') return;

	NodeId attr_scope = id;
	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL || n.kind == NodeKind.ATTRMACRO_DECL)
	{
		attr_scope = n.lhs;
	}

	DeclVis vis = DeclVis.PUBLIC;
	int format_param = -1;
	if (attr_scope != parser::NONE && ast.kind(attr_scope).is_list_bearing())
	{
		foreach (c : ast.children(attr_scope))
		{
			if (c == parser::NONE || ast.kind(c) != NodeKind.ATTR) continue;
			String attr_name = toks.text_at(ast.node(c).tok);
			if (attr_name == "@private") { vis = DeclVis.PRIVATE; }
			else if (attr_name == "@local") { vis = DeclVis.LOCAL; }
			else if (attr_name == "@format")
			{
				NodeId[] akids = ast.children(c);
				if (akids.len >= 2 && akids[1] != parser::NONE && ast.kind(akids[1]) == NodeKind.INT_LIT)
				{
					format_param = string::to_integer{int}(toks.text_at(ast.node(akids[1]).tok)) ?? -1;
				}
			}
		}
	}

	t.decls.push({
		.mod          = mod.len ? mod.copy(a) : "",
		.name         = name.copy(a),
		.kind         = n.kind,
		.vis          = vis,
		.format_param = format_param,
	});
}

<* The full dotted text of a `::`-separated path node (`foo::bar::baz`), reconstructed token by token. *>
fn String path_text(TokenList* toks, Node* n, Allocator a) @local
{
	if (n.first_tok == n.last_tok) return toks.text_at(n.tok).copy(a);
	DString s;
	s.init(a);
	for (uint i = n.first_tok; i <= n.last_tok; i++) s.append(toks.text_at(i));
	return s.str_view();
}

<*
 Locate the standard library's source root.

 `C3VET_STDLIB`, if set, wins outright. Otherwise derive it from the `c3c`
 binary found on `PATH`: `<dir>/../lib/c3/std` is where the official
 installer puts it alongside the compiler. Returns `""` rather than erroring
 when neither resolves -- `missing-format-attr` degrades to project-only
 knowledge rather than failing the run, see the module doc comment above.
*>
fn String find_stdlib_root(Allocator a)
{
	String? override = env::get_var(a, "C3VET_STDLIB");
	if (try override && override.len) return override;

	String? path_env = env::get_var(tmem, "PATH");
	if (catch path_env) return "";

	usz from = 0;
	while (from < path_env.len)
	{
		usz end = from;
		while (end < path_env.len && path_env[end] != ':') end++;
		String dir = path_env[from..end - 1];
		if (dir.len)
		{
			String candidate = string::tformat("%s/c3c", dir);
			if (path::exists(path::tnew(candidate) ?? (Path){}) && !file::is_dir(candidate))
			{
				// Official release tarballs ship "lib/std" next to the
				// binary; some distro packages put it at "../lib/c3/std"
				// instead. Try both.
				String sibling_std = string::format(a, "%s/lib/std", dir);
				if (path::exists(path::tnew(sibling_std) ?? (Path){})) return sibling_std;

				String std = string::format(a, "%s/../lib/c3/std", dir);
				if (path::exists(path::tnew(std) ?? (Path){})) return std;
				return "";
			}
		}
		from = end + 1;
	}
	return "";
}
