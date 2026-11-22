<*
 `empty-body`: an if/while body that is an empty block with no comment
 inside it.

 "No comment inside" means no LINE_COMMENT/BLOCK_COMMENT trivia token between
 the block's opening and closing brace -- a block that is empty except for an
 explanatory comment is deliberate, not a bug, so it must not fire here.
*>
module c3vet;

import c3::lexer;
import c3::parser;
import std::core::mem::alloc;

const Check EMPTY_BODY = {
	.name          = "empty-body",
	.doc           = "An if/while body that is an empty "
		"block with no comment inside.",
	.tier          = Tier.SYNTAX,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_empty_body,
	.make_state    = &make_empty_body_state,
};

<* Carries the engine's two pointers through `walk`'s `any` context. *>
struct EmptyBodyWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_empty_body_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, EmptyBodyWalker, { .ctx = ctx, .unit = u });

fn bool visit_empty_body(Ast* ast, NodeId id, any ctx) @local
{
	EmptyBodyWalker* w = (EmptyBodyWalker*)ctx;
	Node* n = ast.node(id);
	switch (n.kind)
	{
		case IF:
		{
			NodeId[] kids = ast.children(id);
			report_if_empty(w, ast, kids[1]);
			report_if_empty(w, ast, kids[2]);
		}
		case WHILE:
			report_if_empty(w, ast, n.rhs);
		default:
			break;
	}
	return true;
}

fn void report_if_empty(EmptyBodyWalker* w, Ast* ast, NodeId body) @local
{
	if (is_empty_commentless_block(ast, w.unit.toks(), body))
	{
		w.ctx.report(w.unit, body, "empty-body",
			"empty body -- remove the dead statement, or fill in the intended body");
	}
}

fn bool is_empty_commentless_block(Ast* ast, TokenList* toks, NodeId id) @local
{
	if (id == parser::NONE) return false;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.BLOCK) return false;
	if (ast.children(id).len) return false;
	return !block_has_comment(toks, n.first_tok, n.last_tok);
}

<* True when a LINE_COMMENT/BLOCK_COMMENT trivia token lies between the two code tokens. *>
fn bool block_has_comment(TokenList* toks, uint first_tok, uint last_tok) @local
{
	uint start = toks.code[(sz)first_tok];
	uint end = toks.code[(sz)last_tok];
	for (uint i = start + 1; i < end; i++)
	{
		TokenType t = toks.all[(sz)i].type;
		if (t == LINE_COMMENT || t == BLOCK_COMMENT) return true;
	}
	return false;
}
