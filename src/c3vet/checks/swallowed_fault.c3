<* Warn when a catch condition silently discards a fault in an empty branch. *>
module c3vet;

import c3::parser;
import c3::lexer;

const Check SWALLOWED_FAULT = {
	.name          = "swallowed-fault",
	.doc           = "an empty catch branch silently discards a fault",
	.tier          = Tier.LOCAL,
	.default_on    = true,
	.skip_on_error = true,
	.run           = &run_swallowed_fault,
};

struct SwallowedFaultWalker { Ctx* ctx; Unit* unit; }

fn void run_swallowed_fault(Ctx* ctx, Unit* u)
{
	SwallowedFaultWalker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_swallowed_fault, &w);
}

fn bool visit_swallowed_fault(Ast* ast, NodeId id, any context) @local
{
	SwallowedFaultWalker* w = (SwallowedFaultWalker*)context;
	if (ast.kind(id) != NodeKind.IF) return true;
	NodeId[] kids = ast.children(id);
	if (kids.len < 2 || ast.kind(kids[0]) != NodeKind.CATCH_EXPR) return true;
	NodeId operand = ast.node(kids[0]).lhs;
	if (operand != parser::NONE && ast.kind(operand) == NodeKind.ASSIGN) return true;
	if (is_empty_commentless_catch_block(ast, w.unit.toks(), kids[1]))
	{
		w.ctx.report(w.unit, id, SWALLOWED_FAULT.name, "fault is swallowed by an empty catch branch");
	}
	return true;
}

fn bool is_empty_commentless_catch_block(Ast* ast, TokenList* toks, NodeId id) @local
{
	if (id == parser::NONE || ast.kind(id) != NodeKind.BLOCK || ast.children(id).len != 0) return false;
	Node* n = ast.node(id);
	uint start = toks.code[(sz)n.first_tok];
	uint end = toks.code[(sz)n.last_tok];
	for (uint i = start + 1; i < end; i++)
	{
		TokenType t = toks.all[(sz)i].type;
		if (t == LINE_COMMENT || t == BLOCK_COMMENT) return false;
	}
	return true;
}
