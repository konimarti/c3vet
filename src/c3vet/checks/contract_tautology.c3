<*
 `contract-tautology`: a `@require` clause of the form `X == X` -- the
 identical token sequence on both sides of `==`. Always true, so it
 documents nothing a reader couldn't already tell was vacuous.

 Only self-equality is flagged, not tautologies in general. A dotted/member
 path like `a.b == a.b` is flagged too, but a clause containing more than one
 top-level `==` is left alone, as is a clause whose scan is cut short by a
 ternary's own `:`. These cases are missed, never misreported.

 `X == X` is only a tautology when both reads are guaranteed to produce the
 same value: `rand() == rand()` is textually self-identical but not
 tautological, since a call may return something different each time. A
 clause whose identical span contains a call (any `(`) or `++`/`--` is left
 alone.
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
	uint ct = toks.contract_before(n.first_tok);
	if (ct == parser::NO_TOKEN) return true;

	if (contract_has_tautological_require(toks.all[(sz)ct].text))
	{
		w.ctx.report(w.unit, id, "contract-tautology",
			"@require compares an expression to itself -- fix the comparison, it currently documents nothing");
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

<* True when the span could read a different value each time: a call (any `(`) or `++`/`--`. *>
fn bool span_has_side_effect(Token[] toks, sz start, sz len) @local
{
	for (sz k = 0; k < len; k++)
	{
		TokenType t = toks[start + k].type;
		if (t == LPAREN || t == PLUSPLUS || t == MINUSMINUS) return true;
	}
	return false;
}
