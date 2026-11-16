<*
 Structural expression equality, with a side-effect guard.

 Used by `self-assign`, `self-compare`, `self-op` and `dup-branch`.
 Comparing two identical expressions only suggests a copy-paste bug when
 both reads are guaranteed to produce the same value. `f() == f()` and
 `*p == *p` are not: a call may return something different each time,
 `++`/`--` changes the operand, `=` is itself a side effect, and a
 dereference may read through a pointer whose target changed. `same_expr`
 therefore refuses to compare when either side contains any of those.

 `same_shape` compares structure without that guard, for `dup-branch`,
 where a call or assignment inside an otherwise-identical branch body is
 not a reason to stay quiet.
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
 with no side-effect guard.
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
		// Leaf: compare the full span, so `os::POLLERR` != `os::POLLHUP`.
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
