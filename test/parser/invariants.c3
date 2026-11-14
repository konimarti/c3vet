<*
 Structural invariants on a parsed tree. See docs/DESIGN.md section 6.

 These catch the parser bugs that corpus conformance misses. Invariant 3
 (token coverage) is the one that earns its keep: it makes "we silently did
 not parse $foreach bodies" impossible to ship, because an unparsed region
 shows up as uncovered tokens.
*>
module c3::parser::invariants;

import c3::parser;
import std::collections::list;
import std::io;

struct Report
{
	bool   spans_nest;
	bool   edges_valid;
	bool   tokens_covered;
	<* First failure found, for the test output. *>
	String detail;
	<* Code tokens inside no leaf node's span. *>
	sz     uncovered;
	<* Code tokens inside more than one leaf node's span. *>
	sz     overcovered;
}

fn bool Report.ok(&self) @inline
	=> self.spans_nest && self.edges_valid && self.tokens_covered;

<*
 Check invariants 1-3 on a parsed tree.
 @param r : "a result from parser::parse"
*>
fn Report check(ParseResult* r)
{
	Report rep = { .spans_nest = true, .edges_valid = true, .tokens_covered = true };
	sz ntok = r.toks.len();

	// Invariant 3 needs a per-token cover count, filled in by the walk below.
	List{char} cover;
	cover.tinit();
	for (sz i = 0; i < ntok; i++) cover.push(0);

	check_node(r, parser::NONE == r.ast.root ? parser::NONE : r.ast.root, &rep, &cover, 0);

	for (sz i = 0; i < ntok; i++)
	{
		if (cover[i] == 0) rep.uncovered++;
		if (cover[i] > 1) rep.overcovered++;
	}
	if (rep.uncovered > 0 || rep.overcovered > 0)
	{
		rep.tokens_covered = false;
		if (!rep.detail.len)
		{
			rep.detail = string::tformat("%d token(s) in no node, %d in more than one",
				rep.uncovered, rep.overcovered);
		}
	}
	return rep;
}

<*
 Recursive half of `check`. Verifies invariants 1 and 2 on this node, then
 recurses; marks cover for leaves only, so overlapping leaf spans are caught.
*>
fn void check_node(ParseResult* r, NodeId id, Report* rep, List{char}* cover, uint depth) @local
{
	if (id == parser::NONE) return;
	if (depth > 4096)
	{
		rep.edges_valid = false;
		rep.detail = "tree nests deeper than 4096: probable cycle";
		return;
	}

	// Invariant 2: the id must address a real node.
	if ((sz)id >= r.ast.len())
	{
		rep.edges_valid = false;
		if (!rep.detail.len) rep.detail = string::tformat("node id %d is out of range", id);
		return;
	}

	Node* n = r.ast.node(id);
	sz ntok = r.toks.len();

	// Invariant 1: the span must be ordered and hold the principal token.
	if (n.first_tok > n.last_tok || n.tok < n.first_tok || n.tok > n.last_tok)
	{
		rep.spans_nest = false;
		if (!rep.detail.len)
		{
			rep.detail = string::tformat("node %d (%s) has span [%d,%d] with tok %d",
				id, n.kind, n.first_tok, n.last_tok, n.tok);
		}
	}
	if (ntok > 0 && (sz)n.last_tok >= ntok)
	{
		rep.spans_nest = false;
		if (!rep.detail.len)
		{
			rep.detail = string::tformat("node %d (%s) span ends at %d, past the last token %d",
				id, n.kind, n.last_tok, ntok - 1);
		}
	}

	NodeId[] kids = parser::child_ids(&r.ast, id);
	if (!kids.len)
	{
		// A leaf: it owns its span for coverage purposes.
		for (sz t = (sz)n.first_tok; t <= (sz)n.last_tok && t < ntok; t++) cover.set(t, cover.get(t) + 1);
		return;
	}
	foreach (kid : kids)
	{
		if ((sz)kid >= r.ast.len()) continue;
		Node* c = r.ast.node(kid);
		// Invariant 1: a child's span must sit inside its parent's.
		if (c.first_tok < n.first_tok || c.last_tok > n.last_tok)
		{
			rep.spans_nest = false;
			if (!rep.detail.len)
			{
				rep.detail = string::tformat("child %d (%s) span [%d,%d] escapes parent %d (%s) [%d,%d]",
					kid, c.kind, c.first_tok, c.last_tok, id, n.kind, n.first_tok, n.last_tok);
			}
		}
		check_node(r, kid, rep, cover, depth + 1);
	}
}
