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
				"@%s declaration '%s' is never referenced", vis == DeclVis.LOCAL ? "local" : "private", name);
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

fn bool project_module_has_name(UnusedPrivateDeclWalker* w, String mod, String name, uint own_tok) @local
{
	String root = find_project_root(w.unit.path);
	if (!root.len) return source_has_name(w.unit.toks(), name, own_tok);
	List{String} files;
	files.tinit();
	walk_sources(&files, string::tformat("%s/src", root));
	walk_sources(&files, string::tformat("%s/test", root));
	foreach (path_ : files)
	{
		@pool()
		{
			char[]? bytes = file::load(tmem, path_);
			if (catch bytes) continue;
			String src = (String)bytes;
			TokenList toks;
			toks.init(tmem);
			toks.lex(src);
			ParseResult p = parser::parse(tmem, src);
			if (file_module(&p.ast, &p.toks, p.ast.root) != mod) continue;
			bool own_file = same_file(path_, w.unit.path) || src == w.unit.src;
			if (source_has_name_except(&toks, name, own_file ? own_tok : parser::NONE)) return true;
		};
	}
	// Files outside the conventional source trees may still be supplied as a target.
	return source_has_name(w.unit.toks(), name, own_tok);
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
