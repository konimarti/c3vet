<*
 Warn about force-unwrapping in a function that returns an Optional, where
 `!` could have propagated the fault. Tests and main are exempt.
*>
module c3vet;

import c3::parser;
import std::core::mem::alloc;

const Check FORCE_UNWRAP = {
	.name          = "force-unwrap",
	.doc           =
		"force unwrap in a function returning "
		"an Optional, outside tests and main",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_force_unwrap,
	.make_state    = &make_force_unwrap_state,
};

struct ForceUnwrapWalker
{
	Ctx* ctx;
	Unit* unit;
}

fn any make_force_unwrap_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, ForceUnwrapWalker, { .ctx = ctx, .unit = u });

fn bool visit_force_unwrap(Ast* ast, NodeId id, any context) @local
{
	ForceUnwrapWalker* w = (ForceUnwrapWalker*)context;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FN_DECL) return true;
	String name = w.unit.toks().text_at(n.tok);
	bool exempt = name == "main"
		|| signature_has_test_attr(ast, w.unit.toks(), n.lhs);
	scan_force_unwrap_body(ast,
		w.unit.toks(), n.rhs, exempt, returns_optional(ast, n.lhs), w);
	return true;
}

fn bool returns_optional(Ast* ast, NodeId sig) @local
{
	if (sig == parser::NONE || ast.kind(sig) != NodeKind.SIGNATURE)
	{
		return false;
	}
	NodeId[] kids = ast.children(sig);
	return kids.len && kids[0] != parser::NONE
		&& ast.kind(kids[0]) == NodeKind.TYPE_OPTIONAL;
}

fn bool signature_has_test_attr(Ast* ast, TokenList* toks, NodeId id) @local
{
	if (id == parser::NONE || ast.kind(id) != NodeKind.SIGNATURE) return false;
	Node* n = ast.node(id);
	for (uint i = n.first_tok; i <= n.last_tok; i++)
	{
		if (toks.type_at(i) == AT_IDENT && toks.text_at(i) == "@test")
		{
			return true;
		}
	}
	return false;
}

fn void scan_force_unwrap_body(Ast* ast, TokenList* toks, NodeId id,
	bool exempt, bool optional, ForceUnwrapWalker* w) @local
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.FN_DECL)
	{
		return;
	}
	// a lambda's `!` propagates to its own return type, not the enclosing one
	if (n.kind == NodeKind.LAMBDA)
	{
		optional = returns_optional(ast, ast.children(id)[0]);
	}
	if (!exempt && optional && n.kind == NodeKind.FORCE_UNWRAP
		&& toks.type_at(n.tok) == BANGBANG)
	{
		w.ctx.report(w.unit, id, FORCE_UNWRAP.name,
			"force unwrap may panic in a function that returns an Optional -- propagate the fault with !, or handle it with ?? for a default");
	}
	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id))
		{
			scan_force_unwrap_body(ast, toks, c, exempt, optional, w);
		}
	}
	else
	{
		scan_force_unwrap_body(ast, toks, n.lhs, exempt, optional, w);
		scan_force_unwrap_body(ast, toks, n.rhs, exempt, optional, w);
	}
}
