<*
 Per-function scope map -- every parameter and local, with its
 *declared* type only. No inference: a local with no explicit type
 (`var x = ...`) is recorded with `type = NONE`, and a check that needs a
 type simply finds nothing to match, which is the correct, conservative
 answer for a "false positives not acceptable" check.

 Built once per `Unit` when some enabled check is `Tier.LOCAL` or above, and
 shared by every such check; see `Unit.scopes`.
*>
module c3vet;

import c3::parser;
import std::collections::list;
import std::collections::map;

<* One parameter or local: its own node, name, and declared type (or NONE). *>
struct LocalDecl
{
	NodeId decl;
	String name;
	NodeId type;
}

<* Every function's parameters and locals, keyed by the owning `FN_DECL`. *>
struct Scopes
{
	HashMap{NodeId, LocalDecl[]} by_fn;
}

fn void Scopes.init(&self, Allocator a)
{
	self.by_fn.init(a);
}

<* Every parameter/local declared directly in `fn` (a `FN_DECL` id), in declaration order. Empty if `fn` is unknown or has none. *>
fn LocalDecl[] Scopes.locals_in(&self, NodeId fn_decl)
{
	LocalDecl[]? found = self.by_fn.get(fn_decl);
	if (catch found) return {};
	return found;
}

<*
 The declared type of `name` within `fn`, or `NONE` when not found *or*
 declared more than once in that function (shadowing is rare enough that
 staying quiet on it is the safer default than guessing which one a given
 use site means).
*>
fn NodeId Scopes.declared_type(&self, NodeId fn_decl, String name)
{
	NodeId found = parser::NONE;
	bool seen = false;
	foreach (d : self.locals_in(fn_decl))
	{
		if (d.name != name) continue;
		if (seen) return parser::NONE;
		found = d.type;
		seen = true;
	}
	return found;
}

<* Build a `Scopes` by walking every `FN_DECL` in `ast`, once. *>
fn Scopes build_scopes(Ast* ast, TokenList* toks, Allocator a)
{
	Scopes s;
	s.init(a);
	collect_fn_scopes(ast, toks, ast.root, a, &s);
	return s;
}

fn void collect_fn_scopes(Ast* ast, TokenList* toks, NodeId id, Allocator a, Scopes* s) @local
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL)
	{
		List{LocalDecl} locals;
		locals.init(a);
		collect_params(ast, toks, n.lhs, &locals);
		collect_locals(ast, toks, n.rhs, &locals);
		s.by_fn.set(id, locals.to_array(a));
		return;
	}
	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) collect_fn_scopes(ast, toks, c, a, s);
	}
	else
	{
		collect_fn_scopes(ast, toks, n.lhs, a, s);
		collect_fn_scopes(ast, toks, n.rhs, a, s);
	}
}

<* `sig` is a `SIGNATURE` id (or NONE, for a signature-less declaration). *>
fn void collect_params(Ast* ast, TokenList* toks, NodeId sig, List{LocalDecl}* locals) @local
{
	if (sig == parser::NONE || ast.kind(sig) != NodeKind.SIGNATURE) return;
	foreach (c : ast.children(sig))
	{
		if (ast.kind(c) != NodeKind.PARAM) continue;
		Node* p = ast.node(c);
		if (toks.type_at(p.tok) != IDENT && toks.type_at(p.tok) != CT_IDENT) continue;
		NodeId[] pkids = ast.children(c);
		NodeId type = pkids.len ? pkids[0] : parser::NONE;
		locals.push({ .decl = c, .name = toks.text_at(p.tok), .type = type });
	}
}

<* Walk a function body collecting every `VAR_DECL`, never descending into a nested `FN_DECL`/`MACRO_DECL`/`LAMBDA` (those get their own scope). *>
fn void collect_locals(Ast* ast, TokenList* toks, NodeId id, List{LocalDecl}* locals) @local
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL || n.kind == NodeKind.LAMBDA) return;
	if (n.kind == NodeKind.VAR_DECL)
	{
		locals.push({ .decl = id, .name = toks.text_at(n.tok), .type = n.lhs });
	}
	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) collect_locals(ast, toks, c, locals);
	}
	else
	{
		collect_locals(ast, toks, n.lhs, locals);
		collect_locals(ast, toks, n.rhs, locals);
	}
}
