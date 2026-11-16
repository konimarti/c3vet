<*
 Project-wide declaration table.

 Indexes project sources, lib/*.c3l dependencies and the standard library
 (declarations only, function bodies skipped) and answers questions about
 declarations: "does io::printfn carry @format(n)?", "what does std::math
 export?". Entries from outside the reported files never surface as
 diagnostics.

 Only `missing-format-attr` needs the standard library indexed. If the
 standard library cannot be located, the table is built from project-local
 declarations alone and checks degrade conservatively (fewer findings, never
 false ones). A file the parser cannot fully parse is indexed only up to its
 first unparsed declaration.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import libc;
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
 (`io::printfn(...)` -> `"io"`): the last segment of the imported module
 path, matched against each declaration's module by its last segment.
 `mod` empty means the call was unqualified, so the name must be
 unambiguous across every indexed module. Ambiguous names answer -1 ("no
 `@format` found"), preferring a false negative to a false positive.
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
 walked recursively, including `lib`). Names and module paths are copied into
 `a`, so the table owns its strings.
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
 import -- by any file in `project_files`. A submodule matches its import prefix ("import std::net" covers
 "std::net::tcp").
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
 Blank every top-level `{ ... }` body (nested braces included) before
 handing the file to `parser::parse`, so only declarations are indexed.
 Braces are matched over lexer tokens, so a `"{"` inside a string or comment
 is never mistaken for a body boundary.
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

 `C3VET_STDLIB`, if set, wins outright. Otherwise walk `PATH` for `c3c`
 (`c3c.exe` on Windows), resolve symlinks to the real binary, and look next
 to it: `<dir>/lib/std` (official release tarballs) first, then
 `<dir>/../lib/c3/std` (some distro packages). A `c3c` without a stdlib is
 skipped and the search continues. Returns `""` rather than erroring when
 nothing resolves -- `missing-format-attr` degrades to project-only
 knowledge rather than failing the run, see the module doc comment above.
*>
fn String find_stdlib_root(Allocator a)
{
	String? override = env::get_var(a, "C3VET_STDLIB");
	if (try override && override.len) return override;

	String? path_env = env::get_var(tmem, "PATH");
	if (catch path_env) return "";

	$if env::WIN32:
		return find_stdlib_in_path(path_env, ";", "c3c.exe", a);
	$else
		return find_stdlib_in_path(path_env, ":", "c3c", a);
	$endif
}

<* `find_stdlib_root` on an explicit `PATH` value, separator and binary name, so the Windows form can be tested anywhere. *>
fn String find_stdlib_in_path(String path_env, String sep, String bin, Allocator a)
{
	foreach (dir : path_env.tsplit(sep))
	{
		if (!dir.len) continue;
		String candidate = string::tformat("%s/%s", dir, bin);
		if (!path::exists(path::tnew(candidate) ?? (Path){}) || file::is_dir(candidate)) continue;
		String real_dir = dir_of(resolve_links(candidate));
		String sibling_std = string::format(a, "%s/lib/std", real_dir);
		if (path::exists(path::tnew(sibling_std) ?? (Path){})) return sibling_std;
		String std = string::format(a, "%s/../lib/c3/std", real_dir);
		if (path::exists(path::tnew(std) ?? (Path){})) return std;
	}
	return "";
}

<* The directory part of `p` ("." if it has no separator). *>
fn String dir_of(String p) @local
{
	foreach_r (i, c : p)
	{
		if (c == '/' || c == '\\') return i ? p[:i] : "/";
	}
	return ".";
}

<* Follow symlinks until `p` is a regular file; relative targets are relative to the link's directory. Temp-allocated. *>
fn String resolve_links(String p) @local
{
	$if !env::WIN32:
		for (int hops = 0; hops < 40; hops++)
		{
			char[4096] buf;
			sz n = libc::readlink(p.zstr_tcopy(), &buf, buf.len);
			if (n <= 0 || n >= buf.len) break;
			String target = (String)buf[:n];
			p = target[0] == '/' ? target.tcopy() : string::tformat("%s/%s", dir_of(p), target);
		}
	$endif
	return p;
}
