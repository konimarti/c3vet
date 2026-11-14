<*
 `contract-tautology`: a `@require` clause of the form `X == X` -- the
 identical token sequence on both sides of `==`. Always true, so it
 documents nothing a reader couldn't already tell was vacuous.

 Scoped narrowly to self-equality, per CHECKS.md's own phrasing ("n == n and
 similar") -- not a general tautology prover. A dotted/member path like
 `a.b == a.b` is supported for free (it is just a longer identical token
 run), but a clause containing more than one top-level `==` is left alone
 rather than risk comparing the wrong halves. Likewise a ternary's own `:`
 inside the clause can truncate the scan before the real `==` is reached
 (the same "not a general parser" limitation as the multi-`==` bail) -- a
 missed finding there, never a wrong one.

 `X == X` is only a tautology when both reads are guaranteed to produce the
 same value, same as this codebase's own `same_expr` side-effect veto
 (src/c3vet/checks/support/same_expr.c3) for the Family C checks: `rand() ==
 rand()` is textually self-identical but not tautological, since a call may
 return something different each time. A clause whose identical span
 contains a call (any `(`) or `++`/`--` is left alone for the same reason.

 Contracts are trivia, never AST nodes (docs/DESIGN.md section 2): read via
 `TokenList.contract_before` plus `lexer::ContractLexer`, the only bridge.
 `ContractLexer` yields a flat token stream with no expression tree, so this
 is token matching, not AST matching -- and, verified empirically (not
 assumed), its `EOL` token only appears where the source contract text has
 an actual newline between clauses. Two `@require` clauses packed onto one
 line with no separator at all produce no token between them -- the next
 clause's own `AT_IDENT` is the only boundary marker in that case. Clause
 scanning below treats AT_IDENT/COLON/EOL/end-of-stream as the complete set
 of boundary markers precisely because of that.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import std::core::mem::alloc;

const Check CONTRACT_TAUTOLOGY = {
	.name          = "contract-tautology",
	.doc           = "a @require clause compares an expression to itself with ==",
	.tier          = Tier.LOCAL,
	.default_on    = true,
	.skip_on_error = true,
	.visit         = &visit_contract_tautology,
	.make_state    = &make_contract_tautology_state,
};

struct ContractTautologyWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_contract_tautology_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, ContractTautologyWalker, { .ctx = ctx, .unit = u });

fn bool visit_contract_tautology(Ast* ast, NodeId id, any context) @local
{
	ContractTautologyWalker* w = (ContractTautologyWalker*)context;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FN_DECL && n.kind != NodeKind.MACRO_DECL) return true;

	TokenList* toks = w.unit.toks();
	// n.first_tok, not n.tok -- see contract_void_return.c3 for why.
	uint ct = toks.contract_before(n.first_tok);
	if (ct == parser::NO_TOKEN) return true;

	if (contract_has_tautological_require(toks.all[(sz)ct].text))
	{
		w.ctx.report(w.unit, id, "contract-tautology", "@require compares an expression to itself");
	}
	return true;
}

fn bool contract_has_tautological_require(String contract_text) @local
{
	ContractLexer cl;
	cl.init(contract_text);

	List{Token} all;
	all.tinit();
	while (true)
	{
		Token? t = cl.next();
		if (catch t) break;
		all.push(t);
	}
	Token[] toks = all.to_tarray();

	sz i = 0;
	while (i < toks.len)
	{
		if (toks[i].type != AT_IDENT || toks[i].text != "@require")
		{
			i++;
			continue;
		}

		sz clause_start = i + 1;
		sz j = clause_start;
		sz eq_pos = clause_start;
		bool found_eq = false;
		bool bail = false;
		while (j < toks.len && toks[j].type != AT_IDENT && toks[j].type != COLON && toks[j].type != EOL)
		{
			if (toks[j].type == EQEQ)
			{
				if (found_eq) { bail = true; }
				else { eq_pos = j; found_eq = true; }
			}
			j++;
		}

		if (!bail && found_eq)
		{
			sz lhs_len = eq_pos - clause_start;
			sz rhs_len = j - (eq_pos + 1);
			if (lhs_len > 0 && lhs_len == rhs_len
				&& same_tokens(toks, clause_start, eq_pos + 1, lhs_len)
				&& !span_has_side_effect(toks, clause_start, lhs_len))
			{
				return true;
			}
		}
		i = j;
	}
	return false;
}

<* True when `toks[a..a+len)` and `toks[b..b+len)` have identical text, element by element. *>
fn bool same_tokens(Token[] toks, sz a, sz b, sz len) @local
{
	for (sz k = 0; k < len; k++)
	{
		if (toks[a + k].text != toks[b + k].text) return false;
	}
	return true;
}

<*
 True when the span could read a different value each time: a call (any
 `(`, since there is no AST here to tell a call from a parenthesized
 sub-expression -- conservative either way) or `++`/`--`. `X == X` is only
 a tautology when both reads are guaranteed equal; `rand() == rand()` is
 textually self-identical but not tautological.
*>
fn bool span_has_side_effect(Token[] toks, sz start, sz len) @local
{
	for (sz k = 0; k < len; k++)
	{
		TokenType t = toks[start + k].type;
		if (t == LPAREN || t == PLUSPLUS || t == MINUSMINUS) return true;
	}
	return false;
}
