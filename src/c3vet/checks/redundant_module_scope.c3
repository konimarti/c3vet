<*
 `redundant-module-scope`: a module-qualified type reference that would
 resolve to the exact same declaration with no qualifier at all, or a
 qualified call with more leading path segments than the one that is
 always idiomatic.

 A qualifier earns its place only by resolving a genuine collision: two or
 more reachable declarations sharing the final name (C3 spec, Name
 resolution: "only as many leading path components as necessary to
 disambiguate the name need be supplied"). Real c3c stdlib usage backs
 this up, with one twist discovered empirically (see below):

  - A type reference: any qualifier at all is one too many. Every
    qualified type reference actually found in the stdlib (`Win32_DWORD`,
    `Inflater`, `TypeNotSet`) turned out to name the file's own current
    module, and in each case the very same file also used the bare name
    for the identical type elsewhere -- proof the qualifier was an
    inconsistency, not a deliberate choice.
  - A qualified call: one segment is always allowed, full stop, even when
    it is a self-reference. `std::math::random`'s seed-generation macro is
    called as `random::make_seed(...)` from half a dozen sibling files in
    that same module, consistently, with no bare counterexample anywhere
    -- a deliberate "which shared helper this is" convention for a module
    split across files, not noise. So self-reference only ever lowers the
    *type* floor, never the call floor; a second or further leading
    segment on a call is flagged once it is provably decorative.

 Two independent, conservative gates decide "provably":
  - Self-reference (types only): the qualifier names the file's own
    current module. A duplicate name in the same module is a compile
    error on its own, so this can never be an accidental collision --
    always safe to flag, no table lookup needed.
  - Cross-module (types and calls): the final name has to be the only
    PUBLIC declaration of that name anywhere in the indexed project +
    stdlib. Any ambiguity -- including "we don't know" -- keeps the check
    quiet; a missed finding beats a wrong one.
*>
module c3vet;

import c3::parser;
import std::collections::list;
import std::core::mem::alloc;

const Check REDUNDANT_MODULE_SCOPE = {
	.name          = "redundant-module-scope",
	.doc           =
		"a module qualifier that resolves the "
		"same with fewer (or no) path segments",
	.tier          = Tier.PROJECT,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_redundant_module_scope,
	.make_state    = &make_redundant_module_scope_state,
};

struct RedundantModuleScopeWalker
{
	Ctx*   ctx;
	Unit*  unit;
	<* The module declared by the most recently seen top-level `module` section. *>
	String cur_mod;
}

fn any make_redundant_module_scope_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, RedundantModuleScopeWalker,
		{ .ctx = ctx, .unit = u, .cur_mod = "" });

fn bool visit_redundant_module_scope(Ast* ast, NodeId id, any context) @local
{
	RedundantModuleScopeWalker* w = (RedundantModuleScopeWalker*)context;
	if (!w.ctx.table) return true;
	Node* n = ast.node(id);

	if (n.kind == NodeKind.MODULE)
	{
		NodeId[] kids = ast.children(id);
		if (kids.len && kids[0] != parser::NONE)
		{
			Node* path = ast.node(kids[0]);
			w.cur_mod = strip_trailing_scope(span_text(w.unit.toks(),
				path.first_tok, path.last_tok));
		}
		return true;
	}

	if (n.kind == NodeKind.TYPE_NAME && n.lhs != parser::NONE)
	{
		Node* qualifier = ast.node(n.lhs);
		String mod = strip_trailing_scope(span_text(w.unit.toks(),
			qualifier.first_tok, qualifier.last_tok));
		int segs = count_scope_tokens(w.unit.toks(), qualifier.first_tok,
			qualifier.last_tok);
		String name = w.unit.toks().text_at(n.tok);
		check_qualifier(w, id, mod, segs, name, /* floor */ 0,
			/* allow_self_ref */ true);
		return true;
	}

	if (n.kind == NodeKind.CALL)
	{
		NodeId[] kids = ast.children(id);
		if (kids.len && kids[0] != parser::NONE
			&& ast.kind(kids[0]) == NodeKind.PATH)
		{
			Node* path = ast.node(kids[0]);
			if (path.last_tok >= path.first_tok + 2)
			{
				String mod = call_qualifier(w.unit.toks(), path);
				int segs = count_scope_tokens(w.unit.toks(), path.first_tok,
					path.last_tok);
				String name = w.unit.toks().text_at(path.last_tok);
				// Self-reference never lowers a call's floor below 1 --
				// see the module doc comment's `random::make_seed` case.
				check_qualifier(w, kids[0], mod, segs, name, /* floor */ 1,
					/* allow_self_ref */ false);
			}
		}
		return true;
	}

	return true;
}

<*
 Flag `mod`'s qualifier on `name` if it is provably decorative: either (when
 `allow_self_ref`) `mod` is the file's own current module, or `name` is the
 only PUBLIC declaration with that name anywhere indexed, so no shorter form
 could possibly resolve to something else. `floor` is how many segments are
 always allowed; self-reference lowers it to 0.
*>
fn void check_qualifier(RedundantModuleScopeWalker* w, NodeId report_node,
	String mod, int segs, String name, int floor, bool allow_self_ref) @local
{
	if (!mod.len || !name.len) return;
	bool self_ref = allow_self_ref && qualifier_names_module(w.cur_mod, mod);
	int effective_floor = self_ref ? 0 : floor;
	if (segs <= effective_floor) return;
	if (!self_ref && count_public_decls_named(w.ctx.table, name) != 1) return;

	String full = string::tformat("%s::%s", mod, name);
	String minimal = effective_floor == 0
		? name
		: string::tformat("%s::%s", last_segment(mod), name);
	w.ctx.report(w.unit, report_node, REDUNDANT_MODULE_SCOPE.name,
		"module qualifier on '%s' is unnecessary here -- '%s' alone resolves to the same declaration",
		full, minimal);
}

<*
 Whether `qualifier` -- as written at a use site, possibly shortened by
 trailing-segment path-shortening -- names `mod`, the file's own current
 module. Same rule as `module_qualifier_matches` in `table.c3`, duplicated
 here rather than shared: a `@local` helper is file-scoped in C3.
*>
fn bool qualifier_names_module(String mod, String qualifier) @local
{
	if (mod == qualifier) return true;
	if (!mod.ends_with(qualifier)) return false;
	usz prefix_len = mod.len - qualifier.len;
	return prefix_len >= 2 && mod[prefix_len - 1] == ':'
		&& mod[prefix_len - 2] == ':';
}

fn sz count_public_decls_named(DeclTable* t, String name) @local
{
	sz n = 0;
	foreach (&d : t.decls)
	{
		if (d.vis == DeclVis.PUBLIC && d.name == name) n++;
	}
	return n;
}

<* `foo::bar` -> `bar`; a `mod` with no `::` is returned as-is. *>
fn String last_segment(String mod) @local
{
	for (usz i = mod.len; i > 1; i--)
	{
		if (mod[i - 1] == ':' && mod[i - 2] == ':') return mod[i..];
	}
	return mod;
}

fn String strip_trailing_scope(String s) @local
{
	if (s.len >= 2 && s[s.len - 2] == ':' && s[s.len - 1] == ':')
	{
		return s[:s.len - 2];
	}
	return s;
}

fn int count_scope_tokens(TokenList* toks, uint first, uint last) @local
{
	int n = 0;
	for (uint i = first; i <= last; i++) if (toks.type_at(i) == SCOPE) n++;
	return n;
}

<* Every token in `[first, last]`, concatenated. *>
fn String span_text(TokenList* toks, uint first, uint last) @local
{
	DString s;
	s.tinit();
	for (uint i = first; i <= last; i++) s.append(toks.text_at(i));
	return s.str_view();
}

<* A `CALL` callee `PATH`'s qualifier text, excluding the trailing `::name`. *>
fn String call_qualifier(TokenList* toks, Node* path) @local
	=> span_text(toks, path.first_tok, path.last_tok - 2);
