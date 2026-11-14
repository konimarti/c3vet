<*
 Structural expression equality, with a side-effect guard.

 Shared by every Family C check (`self-assign`, `self-compare`, `self-op`,
 `dup-branch`): comparing two syntactically identical expressions is only
 evidence of a copy-paste bug when both reads are guaranteed to produce the
 same value. `f() == f()` and `*p == *p` are not guaranteed that -- a call
 may return something different each time, `++`/`--` changes the operand,
 `=` is itself a side effect, and a dereference may read through a pointer
 whose target changed between the two reads (this is also the parser's only
 reachable proxy for "volatile load": there is no VOLATILE node kind, so a
 plain deref is treated as potentially-volatile and excluded, conservatively,
 rather than risk a false positive). So `same_expr` refuses to compare at all
 when either side contains any of those four shapes anywhere in its subtree.

 That guard only makes sense for expression-identity checks ("this one read
 is guaranteed to equal that one read"). `dup-branch` is a different
 question -- "was this code copy-pasted?" -- where a call or assignment
 inside an otherwise-identical branch body is not a reason to stay quiet;
 only one branch of an if/else-if chain ever runs, so there is no "two reads"
 to worry about. `same_shape` is exported separately for that case: the same
 recursive structural comparison, without the side-effect veto.
*>
module c3vet;

import c3::parser;
import c3::lexer;

<*
 True when `a` and `b` are the same expression: equal kind and token text at
 every node, recursively -- unless either subtree could have a side effect,
 in which case this always returns false, regardless of shape.
*>
fn bool same_expr(Ast* ast, TokenList* toks, NodeId a, NodeId b)
{
	if (a == parser::NONE || b == parser::NONE) return a == b;
	if (has_side_effect(ast, toks, a)) return false;
	if (has_side_effect(ast, toks, b)) return false;
	return same_shape(ast, toks, a, b);
}

<*
 Recursive structural comparison: equal kind and token text at every node,
 with no side-effect guard. Used directly by `same_expr` (after its guard
 passes) and by `dup-branch` (which does not want the guard at all -- see
 the module doc comment above).
*>
fn bool same_shape(Ast* ast, TokenList* toks, NodeId a, NodeId b)
{
	if (a == parser::NONE || b == parser::NONE) return a == b;
	Node* na = ast.node(a);
	Node* nb = ast.node(b);
	if (na.kind != nb.kind) return false;

	if (na.kind.is_list_bearing())
	{
		NodeId[] ca = ast.children(a);
		NodeId[] cb = ast.children(b);
		if (ca.len != cb.len) return false;
		foreach (i, c : ca)
		{
			if (!same_shape(ast, toks, c, cb[i])) return false;
		}
		return true;
	}

	if (na.lhs == parser::NONE && na.rhs == parser::NONE && nb.lhs == parser::NONE && nb.rhs == parser::NONE)
	{
		// A true leaf (IDENT, PATH, literals, ...). `.tok` is only an anchor,
		// not the whole identity -- a qualified PATH's `.tok` is its first
		// segment, so `os::POLLERR` and `os::POLLHUP` would otherwise compare
		// equal on that one token alone. Compare the full node span instead.
		if (na.last_tok - na.first_tok != nb.last_tok - nb.first_tok) return false;
		for (uint i = 0; i <= na.last_tok - na.first_tok; i++)
		{
			if (toks.text_at(na.first_tok + i) != toks.text_at(nb.first_tok + i)) return false;
		}
		return true;
	}

	if (toks.text_at(na.tok) != toks.text_at(nb.tok)) return false;
	return same_shape(ast, toks, na.lhs, nb.lhs) && same_shape(ast, toks, na.rhs, nb.rhs);
}

<*
 True when `id` or anything beneath it is a call, `++`/`--`, an assignment,
 or a dereference.
*>
fn bool has_side_effect(Ast* ast, TokenList* toks, NodeId id) @local
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
			if (has_side_effect(ast, toks, c)) return true;
		}
		return false;
	}
	return has_side_effect(ast, toks, n.lhs) || has_side_effect(ast, toks, n.rhs);
}
