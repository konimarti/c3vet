<* Report imports unused by qualified paths and unqualified exported names. *>
module c3vet;

import c3::parser;
import c3::lexer;

const Check UNUSED_IMPORT = {
	.name          = "unused-import",
	.doc           = "an imported module is not referenced in this file",
	.tier          = Tier.PROJECT,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_unused_import,
};

struct UnusedImportWalker { Ctx* ctx; Unit* unit; }

fn void run_unused_import(Ctx* ctx, Unit* u)
{
	if (!ctx.table) return;
	UnusedImportWalker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_unused_import, &w);
}

fn bool visit_unused_import(Ast* ast, NodeId id, any context) @local
{
	UnusedImportWalker* w = (UnusedImportWalker*)context;
	if (ast.kind(id) != NodeKind.IMPORT) return true;
	foreach (child : ast.children(id))
	{
		if (ast.kind(child) != NodeKind.PATH) continue;
		String mod = path_text(ast, w.unit.toks(), child);
		String imported_as = w.unit.toks().text_at(ast.node(child).last_tok);
		String[] names = w.ctx.table.exported_names(tmem, mod);
		bool known_exports = false;
		foreach (name : names)
		{
			if (name == "def" || name == "faultdef") continue;
			known_exports = true;
			break;
		}
		// With no usable table entries we cannot prove this import unused.
		if (!known_exports) continue;
		if (file_uses_import(ast, w.unit.toks(), mod, imported_as, names)) continue;
		w.ctx.report(w.unit, id, UNUSED_IMPORT.name, "import '%s' is unused", mod);
	}
	return true;
}

fn bool file_uses_import(Ast* ast, TokenList* toks, String mod, String imported_as, String[] exports) @local
{
	for (uint i = 0; i < toks.len(); i++)
	{
		if (is_module_or_import_token(ast, i)) continue;
		if (tokens_have_module_prefix(toks, i, mod) || tokens_have_module_prefix(toks, i, imported_as)) return true;
		if (i > 0 && toks.type_at(i - 1) == SCOPE) continue;
		String name = toks.text_at(i);
		foreach (exported : exports)
		{
			if (exported == "def" || exported == "faultdef") continue;
			if (name == exported) return true;
		}
	}
	return false;
}

fn bool is_module_or_import_token(Ast* ast, uint tok) @local
{
	foreach (id : ast.children(ast.root))
	{
		Node* n = ast.node(id);
		if (n.kind != NodeKind.MODULE && n.kind != NodeKind.IMPORT) continue;
		if (tok >= n.first_tok && tok <= n.last_tok) return true;
	}
	return false;
}

<* PATH leaves store the full qualified path only in their token span. *>
fn String path_text(Ast* ast, TokenList* toks, NodeId id) @local
{
	Node* n = ast.node(id);
	if (n.first_tok == n.last_tok) return toks.text_at(n.tok);
	DString s;
	s.init(tmem);
	for (uint i = n.first_tok; i <= n.last_tok; i++) s.append(toks.text_at(i));
	return s.str_view();
}

<* Compare a token sequence to a module path; require the following scope operator. *>
fn bool tokens_have_module_prefix(TokenList* toks, uint first, String mod) @local
{
	usz offset = 0;
	uint at = first;
	while (offset < mod.len)
	{
		usz end = offset;
		while (end + 1 < mod.len && (mod[end] != ':' || mod[end + 1] != ':')) end++;
		usz segment_end = end + 1 < mod.len ? end : mod.len;
		if (at >= toks.len() || !token_matches_segment(toks, at, mod, offset, segment_end)) return false;
		at++;
		if (segment_end == mod.len) return at < toks.len() && toks.type_at(at) == SCOPE;
		if (toks.type_at(at) != SCOPE) return false;
		at++;
		offset = segment_end + 2;
	}
	return false;
}

fn bool token_matches_segment(TokenList* toks, uint tok, String whole, usz start, usz end) @local
{
	String text = toks.text_at(tok);
	if (text.len != end - start) return false;
	for (usz i = 0; i < text.len; i++) if (text[i] != whole[start + i]) return false;
	return true;
}
