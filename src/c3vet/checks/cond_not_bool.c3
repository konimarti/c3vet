<*
 `cond-not-bool`: `if (n)` / `while (n)` where `n` is a bare variable
 *declared* integer or pointer. C3 permits this deliberately (any integer or
 pointer is truthy when non-zero), but it reads easily as a boolean by
 mistake, so it is worth flagging even though the compiler does not.
*>
module c3vet;

import c3::parser;
import c3::lexer;

const Check COND_NOT_BOOL = {
	.name          = "cond-not-bool",
	.doc           = "if/while condition is a bare integer- or pointer-declared variable, not a boolean",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_cond_not_bool,
};

struct CondNotBoolWalker
{
	Ctx*   ctx;
	Unit*  unit;
	NodeId current_fn;
}

fn void run_cond_not_bool(Ctx* ctx, Unit* u)
{
	CondNotBoolWalker w = { .ctx = ctx, .unit = u, .current_fn = parser::NONE };
	parser::walk(u.ast(), u.root(), &visit_cond_not_bool, &w);
}

fn bool visit_cond_not_bool(Ast* ast, NodeId id, any context) @local
{
	CondNotBoolWalker* w = (CondNotBoolWalker*)context;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL)
	{
		w.current_fn = id;
		return true;
	}
	// Scopes never indexes a LAMBDA's own locals (see scope.c3's
	// collect_locals), so a name inside one cannot be resolved against the
	// enclosing function's scope without risking a shadowed-name mix-up.
	if (n.kind == NodeKind.LAMBDA) return false;

	NodeId cond = parser::NONE;
	switch (n.kind)
	{
		case IF:
			cond = ast.children(id)[0];
		case WHILE:
			cond = n.lhs;
		default:
			return true;
	}
	check_condition(ast, w, cond);
	return true;
}

fn void check_condition(Ast* ast, CondNotBoolWalker* w, NodeId cond) @local
{
	if (cond == parser::NONE || w.current_fn == parser::NONE) return;
	Node* n = ast.node(cond);
	if (n.kind != NodeKind.IDENT) return;
	TokenList* toks = w.unit.toks();
	String name = toks.text_at(n.tok);
	NodeId type = w.unit.scopes.declared_type(w.current_fn, name);
	if (type == parser::NONE) return;

	if (ast.kind(type) == NodeKind.TYPE_PTR)
	{
		w.ctx.report(w.unit, cond, "cond-not-bool", "condition '%s' is a pointer, not a boolean expression", name);
	}
	else if (is_integer_type(ast, toks, type))
	{
		w.ctx.report(w.unit, cond, "cond-not-bool",
			"condition '%s' is a declared '%s', not a boolean expression", name, toks.text_at(ast.node(type).tok));
	}
}

fn bool is_integer_type(Ast* ast, TokenList* toks, NodeId type) @local
{
	if (type == parser::NONE || ast.kind(type) != NodeKind.TYPE_BASE) return false;
	switch (toks.text_at(ast.node(type).tok))
	{
		case "char":
		case "ichar":
		case "short":
		case "ushort":
		case "int":
		case "uint":
		case "long":
		case "ulong":
		case "int128":
		case "uint128":
		case "iptr":
		case "uptr":
		case "isz":
		case "usz":
			return true;
		default:
			return false;
	}
}
