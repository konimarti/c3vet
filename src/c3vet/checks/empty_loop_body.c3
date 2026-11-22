<*
 `empty-loop-body`: a for/while/do/foreach loop whose body is an empty block
 and whose condition (or, for foreach, the iterated collection) has no side
 effect.

 Opt-in (`default_on = false`): `while (true) {}` legitimately fires here --
 a busy-wait with a side-effect-free condition and a truly empty body is
 exactly what this check targets. A loop whose condition has a side effect
 (a call, `++`/`--`, an assignment) is not flagged.
*>
module c3vet;

import c3::lexer;
import c3::parser;
import std::core::mem::alloc;

const Check EMPTY_LOOP_BODY = {
	.name          = "empty-loop-body",
	.doc           =
		"A loop whose body is empty and whose condition has no side effects.",
	.tier          = Tier.SYNTAX,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_empty_loop_body,
	.make_state    = &make_empty_loop_body_state,
};

<* Carries the engine's two pointers through `walk`'s `any` context. *>
struct EmptyLoopBodyWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_empty_loop_body_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, EmptyLoopBodyWalker, { .ctx = ctx, .unit = u });

fn bool visit_empty_loop_body(Ast* ast, NodeId id, any ctx) @local
{
	EmptyLoopBodyWalker* w = (EmptyLoopBodyWalker*)ctx;
	Node* n = ast.node(id);
	NodeId cond = parser::NONE;
	NodeId body = parser::NONE;
	switch (n.kind)
	{
		case WHILE:
			cond = n.lhs;
			body = n.rhs;
		case DO:
			body = n.lhs;
			cond = n.rhs;
		case FOR:
		{
			NodeId[] kids = ast.children(id);
			cond = kids[1];
			body = kids[3];
		}
		case FOREACH:
		case FOREACH_R:
		{
			NodeId[] kids = ast.children(id);
			cond = kids[0];
			body = kids[1];
		}
		default:
			return true;
	}
	if (is_empty_block(ast, body) && !loop_has_side_effect(ast,
		w.unit.toks(), cond))
	{
		w.ctx.report(w.unit, body, "empty-loop-body",
			"empty loop body -- remove the loop, or add the work it's supposed to do");
	}
	return true;
}

fn bool is_empty_block(Ast* ast, NodeId id) @local
{
	if (id == parser::NONE) return false;
	Node* n = ast.node(id);
	return n.kind == NodeKind.BLOCK && !ast.children(id).len;
}

<* True when `id` or anything beneath it is a call, `++`/`--`, an assignment, or a dereference. *>
fn bool loop_has_side_effect(Ast* ast, TokenList* toks, NodeId id) @local
{
	if (id == parser::NONE) return false;
	Node* n = ast.node(id);
	switch (n.kind)
	{
		case CALL:
		case CT_CALL:
		case ASSIGN:
			return true;
		case UNARY:
		case POSTFIX:
		{
			TokenType op = toks.type_at(n.tok);
			if (op == PLUSPLUS || op == MINUSMINUS || op == STAR) return true;
		}
		default:
			break;
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id))
		{
			if (loop_has_side_effect(ast, toks, c)) return true;
		}
		return false;
	}
	return loop_has_side_effect(ast, toks, n.lhs)
		|| loop_has_side_effect(ast, toks, n.rhs);
}
