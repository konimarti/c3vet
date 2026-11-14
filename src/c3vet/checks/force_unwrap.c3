<* Warn about force-unwrapping outside tests and main. *>
module c3vet;

import c3::parser;
import c3::lexer;
import std::core::mem::alloc;

const Check FORCE_UNWRAP = {
	.name          = "force-unwrap",
	.doc           = "force unwrap outside a test or main function",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_force_unwrap,
	.make_state    = &make_force_unwrap_state,
};

struct ForceUnwrapWalker { Ctx* ctx; Unit* unit; }

fn any make_force_unwrap_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, ForceUnwrapWalker, { .ctx = ctx, .unit = u });

fn bool visit_force_unwrap(Ast* ast, NodeId id, any context) @local
{
	ForceUnwrapWalker* w = (ForceUnwrapWalker*)context;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FN_DECL) return true;
	String name = w.unit.toks().text_at(n.tok);
	bool allowed = name == "main" || signature_has_test_attr(ast, w.unit.toks(), n.lhs);
	scan_force_unwrap_body(ast, w.unit.toks(), n.rhs, allowed, w);
	return true;
}

fn bool signature_has_test_attr(Ast* ast, TokenList* toks, NodeId id) @local
{
	if (id == parser::NONE || ast.kind(id) != NodeKind.SIGNATURE) return false;
	Node* n = ast.node(id);
	for (uint i = n.first_tok; i <= n.last_tok; i++)
	{
		if (toks.type_at(i) == AT_IDENT && toks.text_at(i) == "@test") return true;
	}
	return false;
}

fn void scan_force_unwrap_body(Ast* ast, TokenList* toks, NodeId id, bool allowed, ForceUnwrapWalker* w) @local
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.FN_DECL)
	{
		return;
	}
	if (!allowed && n.kind == NodeKind.FORCE_UNWRAP && toks.type_at(n.tok) == BANGBANG)
	{
		w.ctx.report(w.unit, id, FORCE_UNWRAP.name,
			"force unwrap may panic outside tests and main -- handle the Optional with ?? for a default, or propagate it with the caller's own !");
	}
	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) scan_force_unwrap_body(ast, toks, c, allowed, w);
	}
	else
	{
		scan_force_unwrap_body(ast, toks, n.lhs, allowed, w);
		scan_force_unwrap_body(ast, toks, n.rhs, allowed, w);
	}
}
