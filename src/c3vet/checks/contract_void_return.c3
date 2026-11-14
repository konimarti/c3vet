<*
 `contract-void-return`: an `@return` clause documented on a function whose
 declared return type is `void`.

 Contracts are trivia, never AST nodes (docs/DESIGN.md section 2): read via
 `TokenList.contract_before` plus `lexer::ContractLexer`, the only bridge --
 nothing else touches contract interiors.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::core::mem::alloc;

const Check CONTRACT_VOID_RETURN = {
	.name          = "contract-void-return",
	.doc           = "an @return contract is documented on a function returning void",
	.tier          = Tier.LOCAL,
	.default_on    = true,
	.skip_on_error = true,
	.visit         = &visit_contract_void_return,
	.make_state    = &make_contract_void_return_state,
};

struct ContractVoidReturnWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_contract_void_return_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, ContractVoidReturnWalker, { .ctx = ctx, .unit = u });

fn bool visit_contract_void_return(Ast* ast, NodeId id, any context) @local
{
	ContractVoidReturnWalker* w = (ContractVoidReturnWalker*)context;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FN_DECL && n.kind != NodeKind.MACRO_DECL) return true;
	if (!returns_void(ast, w.unit.toks(), n.lhs)) return true;

	TokenList* toks = w.unit.toks();
	// n.first_tok, not n.tok -- n.tok is the declared name, mid-signature.
	// A contract is only ever found immediately before a declaration's own
	// first token (its `fn`/`macro` keyword); passing n.tok here silently
	// returns NO_TOKEN every time (verified empirically both ways).
	uint ct = toks.contract_before(n.first_tok);
	if (ct == parser::NO_TOKEN) return true;

	if (contract_has_return(toks.all[(sz)ct].text))
	{
		w.ctx.report(w.unit, id, "contract-void-return", "@return is documented on a function that returns void");
	}
	return true;
}

<* `sig` is the FN_DECL/MACRO_DECL's SIGNATURE id, or NONE for a signature-less declaration. *>
fn bool returns_void(Ast* ast, TokenList* toks, NodeId sig) @local
{
	if (sig == parser::NONE || ast.kind(sig) != NodeKind.SIGNATURE) return false;
	NodeId[] kids = ast.children(sig);
	if (!kids.len || kids[0] == parser::NONE) return false;
	NodeId ret = kids[0];
	return ast.kind(ret) == NodeKind.TYPE_BASE && toks.type_at(ast.node(ret).tok) == VOID;
}

<* True when any `@return` clause marker appears anywhere in the contract. *>
fn bool contract_has_return(String contract_text) @local
{
	ContractLexer cl;
	cl.init(contract_text);
	while (true)
	{
		Token? t = cl.next();
		if (catch t) return false;
		if (t.type == AT_IDENT && t.text == "@return") return true;
	}
}
