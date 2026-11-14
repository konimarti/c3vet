<* Warn when a void cast discards the result of a same-file Optional call. *>
module c3vet;

import c3::parser;
import c3::lexer;

const Check SILENCED_FAULT = {
	.name          = "silenced-fault",
	.doc           = "a void cast discards an Optional-returning call",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_silenced_fault,
};

struct SilencedFaultWalker { Ctx* ctx; Unit* unit; }

fn void run_silenced_fault(Ctx* ctx, Unit* u)
{
	SilencedFaultWalker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_silenced_fault, &w);
}

fn bool visit_silenced_fault(Ast* ast, NodeId id, any context) @local
{
	SilencedFaultWalker* w = (SilencedFaultWalker*)context;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.CAST || n.lhs == parser::NONE || n.rhs == parser::NONE) return true;
	if (ast.kind(n.lhs) != NodeKind.TYPE_BASE || w.unit.toks().type_at(ast.node(n.lhs).tok) != VOID) return true;
	if (ast.kind(n.rhs) != NodeKind.CALL) return true;
	NodeId[] kids = ast.children(n.rhs);
	if (!kids.len) return true;
	String callee = call_name(ast, w.unit.toks(), kids[0]);
	if (callee.len && same_file_optional_function(ast, w.unit.toks(), w.unit.root(), callee))
	{
		w.ctx.report(w.unit, id, SILENCED_FAULT.name, "void cast discards an Optional result from '%s'", callee);
	}
	return true;
}

fn String call_name(Ast* ast, TokenList* toks, NodeId id) @local
{
	if (id == parser::NONE) return "";
	Node* n = ast.node(id);
	if (n.kind == NodeKind.IDENT || n.kind == NodeKind.TYPE_NAME) return toks.text_at(n.tok);
	if (n.kind == NodeKind.MEMBER_ACCESS) return call_name(ast, toks, n.rhs);
	return "";
}

fn bool same_file_optional_function(Ast* ast, TokenList* toks, NodeId id, String name) @local
{
	if (id == parser::NONE) return false;
	Node* n = ast.node(id);
	if ((n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL)
		&& toks.text_at(n.tok) == name && n.lhs != parser::NONE && ast.kind(n.lhs) == NodeKind.SIGNATURE)
	{
		NodeId[] sig = ast.children(n.lhs);
		if (sig.len && sig[0] != parser::NONE && ast.kind(sig[0]) == NodeKind.TYPE_OPTIONAL) return true;
	}
	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) if (same_file_optional_function(ast, toks, c, name)) return true;
		return false;
	}
	return same_file_optional_function(ast, toks, n.lhs, name)
		|| same_file_optional_function(ast, toks, n.rhs, name);
}
