<*
 `float-equal`: `==`/`!=` where either side is a float literal or a bare
 variable *declared* `float`/`double`/`float16`/`bfloat`/`float128`.

 Floating-point equality is almost never the intended comparison -- rounding
 means two values computed differently rarely come out bit-identical.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::core::mem::alloc;

const Check FLOAT_EQUAL = {
	.name          = "float-equal",
	.doc           = "== or != compares a float literal or a float-declared variable",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_float_equal,
	.make_state    = &make_float_equal_state,
};

struct FloatEqualWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_float_equal_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, FloatEqualWalker, { .ctx = ctx, .unit = u });

<*
 Only reacts to FN_DECL/MACRO_DECL, then scans that one function's body with
 its own `fn_decl` id threaded explicitly through the recursion (rather than
 mutable "current function" state on the walker) so a top-level declaration
 after this function can never see a stale function id left over from it.
*>
fn bool visit_float_equal(Ast* ast, NodeId id, any context) @local
{
	FloatEqualWalker* w = (FloatEqualWalker*)context;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FN_DECL && n.kind != NodeKind.MACRO_DECL) return true;
	scan_body(ast, w, id, n.rhs);
	return false;
}

<* Scans `id`'s subtree for `==`/`!=` float comparisons, resolving bare names against `fn_decl`'s scope. *>
fn void scan_body(Ast* ast, FloatEqualWalker* w, NodeId fn_decl, NodeId id) @local
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);

	// Scopes never indexes a LAMBDA's own locals (see scope.c3's
	// collect_locals), so a name inside one cannot be resolved against the
	// enclosing function's scope without risking a shadowed-name mix-up.
	if (n.kind == NodeKind.LAMBDA) return;

	if (n.kind == NodeKind.BINARY)
	{
		TokenType op = w.unit.toks().type_at(n.tok);
		if (op == EQEQ || op == NOT_EQUAL)
		{
			if (is_float_operand(ast, w, fn_decl, n.lhs) || is_float_operand(ast, w, fn_decl, n.rhs))
			{
				w.ctx.report(w.unit, id, "float-equal", "== or != compares floating-point values");
			}
		}
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) scan_body(ast, w, fn_decl, c);
		return;
	}
	scan_body(ast, w, fn_decl, n.lhs);
	scan_body(ast, w, fn_decl, n.rhs);
}

fn bool is_float_operand(Ast* ast, FloatEqualWalker* w, NodeId fn_decl, NodeId id) @local
{
	if (id == parser::NONE) return false;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.REAL_LIT) return true;
	if (n.kind == NodeKind.IDENT)
	{
		NodeId type = w.unit.scopes.declared_type(fn_decl, w.unit.toks().text_at(n.tok));
		return is_float_type(ast, w.unit.toks(), type);
	}
	return false;
}

fn bool is_float_type(Ast* ast, TokenList* toks, NodeId type) @local
{
	if (type == parser::NONE || ast.kind(type) != NodeKind.TYPE_BASE) return false;
	String name = toks.text_at(ast.node(type).tok);
	return name == "float" || name == "double" || name == "float16" || name == "bfloat" || name == "float128";
}
