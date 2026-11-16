<* Report unreferenced @private and @local declarations. *>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import std::io;
import std::io::path;

const Check UNUSED_PRIVATE_DECL = {
	.name          = "unused-private-decl",
	.doc           = "a private or local declaration is never referenced in scope",
	.tier          = Tier.PROJECT,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_unused_private_decl,
};

struct UnusedPrivateDeclWalker { Ctx* ctx; Unit* unit; }

fn void run_unused_private_decl(Ctx* ctx, Unit* u)
{
	if (!ctx.table) return;
	UnusedPrivateDeclWalker w = { .ctx = ctx, .unit = u };
	String mod = file_module(u.ast(), u.toks(), u.root());
	if (!mod.len) return;
	DeclInfo[] indexed = ctx.table.decls_in(tmem, mod);
	foreach (id : parser::child_ids(u.ast(), u.root()))
	{
		Node* n = u.ast().node(id);
		if (!n.kind.is_decl() || n.kind == NodeKind.MODULE || n.kind == NodeKind.IMPORT) continue;
		String name = u.toks().text_at(n.tok);
		if (name == "def" || name == "faultdef" || !name.len) continue;
		DeclVis vis;
		if (!unique_visibility(indexed, name, &vis)) continue;
		if (vis != DeclVis.PRIVATE && vis != DeclVis.LOCAL) continue;
		bool used;
		if (vis == DeclVis.LOCAL)
		{
			used = source_has_name(u.toks(), name, n.tok);
		}
		else
		{
			used = project_module_has_name(&w, mod, name, n.tok);
		}
		if (!used)
		{
			w.ctx.report(w.unit, id, UNUSED_PRIVATE_DECL.name,
				"@%s declaration '%s' is never referenced -- remove it, or make it accessible if other code should use it",
				vis == DeclVis.LOCAL ? "local" : "private", name);
		}
	}
}

fn bool unique_visibility(DeclInfo[] decls, String name, DeclVis* vis) @local
{
	bool found = false;
	foreach (d : decls)
	{
		if (d.name != name) continue;
		if (found) return false;
		*vis = d.vis;
		found = true;
	}
	return found;
}

fn String file_module(Ast* ast, TokenList* toks, NodeId root) @local
{
	foreach (id : ast.children(root))
	{
		if (ast.kind(id) != NodeKind.MODULE) continue;
		NodeId[] kids = ast.children(id);
		if (kids.len && kids[0] != parser::NONE) return path_text(ast, toks, kids[0]);
	}
	return "";
}

fn String path_text(Ast* ast, TokenList* toks, NodeId id) @local
{
	Node* n = ast.node(id);
	if (n.first_tok == n.last_tok) return toks.text_at(n.tok);
	DString s;
	s.init(tmem);
	for (uint i = n.first_tok; i <= n.last_tok; i++) s.append(toks.text_at(i));
	return s.str_view();
}

<* One project file, lexed once and kept for the rest of this run. *>
struct CachedProjectFile
{
	String    path;
	String    mod_name;
	TokenList toks;
}

<* Every project file, lexed once and cached for the rest of the run. *>
struct ProjectFileCache
{
	Ctx*                    built_for;
	List{CachedProjectFile} files;
}

ProjectFileCache g_project_cache @local;

fn void ensure_project_cache(Ctx* ctx, String file_path) @local
{
	if (g_project_cache.built_for == ctx) return;
	g_project_cache.built_for = ctx;
	Allocator a = ctx.out.allocator;
	g_project_cache.files.init(a);

	String root = find_project_root(file_path);
	if (!root.len) return;

	// Walk the whole project root: a module's files may live outside "src"/"test".
	List{String} paths;
	paths.tinit();
	walk_sources(&paths, root);

	foreach (p : paths)
	{
		char[]? bytes = file::load(a, p);
		if (catch bytes) continue;
		String src = (String)bytes;
		TokenList toks;
		toks.init(a);
		toks.lex(src);
		g_project_cache.files.push({
			.path     = p.copy(a),
			.mod_name = module_name_from_tokens(&toks, a),
			.toks     = toks,
		});
	}
}

<* Frees the cached project-file data so a later call rebuilds it. *>
fn void free_project_cache()
{
	if (!g_project_cache.built_for) return;
	foreach (&f : g_project_cache.files) f.toks.free();
	g_project_cache.files.free();
	g_project_cache.built_for = null;
}

<* Scans past the `module` keyword for the dotted path up to the statement's `;`. *>
fn String module_name_from_tokens(TokenList* toks, Allocator a) @local
{
	for (uint i = 0; i < toks.len(); i++)
	{
		if (toks.type_at(i) != MODULE) continue;
		DString s;
		s.init(a);
		// Take only the dotted path; skip a trailing attribute or generic parameters.
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

fn bool project_module_has_name(UnusedPrivateDeclWalker* w, String mod, String name, uint own_tok) @local
{
	ensure_project_cache(w.ctx, w.unit.path);
	if (!g_project_cache.files.len()) return source_has_name(w.unit.toks(), name, own_tok);

	bool found_module = false;
	foreach (&f : g_project_cache.files)
	{
		if (f.mod_name != mod) continue;
		found_module = true;
		bool own_file = same_file(f.path, w.unit.path);
		if (source_has_name_except(&f.toks, name, own_file ? own_tok : parser::NONE)) return true;
	}
	if (!found_module) return source_has_name(w.unit.toks(), name, own_tok);
	return false;
}

fn bool source_has_name(TokenList* toks, String name, uint skip_tok) @local
{
	return source_has_name_except(toks, name, skip_tok);
}

fn bool source_has_name_except(TokenList* toks, String name, uint skip_tok) @local
{
	for (uint i = 0; i < toks.len(); i++)
	{
		if (i == skip_tok) continue;
		if (toks.text_at(i) == name) return true;
	}
	return contract_trivia_has_name(toks, name);
}

<* True when a `@require`/`@ensure` contract references the declaration. *>
fn bool contract_trivia_has_name(TokenList* toks, String name) @local
{
	foreach (t : toks.all)
	{
		if (t.type != CONTRACT || t.text.len < 4) continue;
		ContractLexer cl;
		cl.init(t.text);
		while (true)
		{
			Token? ct = cl.next();
			if (catch ct) break;
			if (ct.text == name) return true;
		}
	}
	return false;
}

fn bool same_file(String a, String b) @local
{
	if (a == b) return true;
	if (a.ends_with(b)) return true;
	return b.starts_with("./") && a.ends_with(b[1..]);
}

fn String find_project_root(String file_path) @local
{
	Path? f = path::tnew(file_path);
	if (catch f) return "";
	Path? parent = f.parent();
	if (catch parent) return "";
	Path dir = parent;
	for (int i = 0; i < 64; i++)
	{
		String marker = string::tformat("%s/project.json", dir);
		if (path::exists(path::tnew(marker) ?? (Path){})) return dir;
		Path? up = dir.parent();
		if (catch up) break;
		if (up == dir) break;
		dir = up;
	}
	return "";
}

fn void walk_sources(List{String}* files, String dir) @local
{
	Path? p = path::tnew(dir);
	if (catch p) return;
	if (!path::exists(p)) return;
	PathList? entries = path::ls(tmem, p);
	if (catch entries) return;
	foreach (e : entries)
	{
		String name = e.basename();
		if (name == "." || name == ".." || name.starts_with(".") || name == "build" || name == "out") continue;
		String full = string::tformat("%s/%s", dir, name);
		if (file::is_dir(full))
		{
			walk_sources(files, full);
		}
		else if (name.ends_with(".c3") || name.ends_with(".c3i"))
		{
			files.push(full);
		}
	}
}
