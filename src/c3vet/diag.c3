<*
 Diagnostics and their rendering.

 FROZEN INTERFACE. See docs/DESIGN.md section 5.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import std::io;

<* The check name used for parse failures, so they render like any finding. *>
const String PARSE_CHECK = "parse";

struct Diagnostic
{
	String file;
	<* 1-based, from the lexer's own token positions. *>
	sz     ln, col;
	<*
	 Token span, retained so a future --fix has an exact range to rewrite.
	 Unused in v1. Indices into the unit's `TokenList.code`.
	*>
	uint   first_tok, last_tok;
	<* The check that reported this, as the user sees it. *>
	String check;
	String msg;
}

alias DiagnosticList = List{Diagnostic};

<*
 Render one finding, go-vet style, on a single line:

   src/parse.c3:42:9: self-assignment of 'count' [self-assign]
*>
fn String Diagnostic.to_string(&self, Allocator a)
	=> string::format(a, "%s:%d:%d: %s [%s]", self.file, self.ln, self.col, self.msg, self.check);

<* Order findings by file, then position, so output is stable across runs. *>
fn int cmp_diagnostic(Diagnostic a, Diagnostic b)
{
	if (a.file != b.file) return a.file.compare_to(b.file);
	if (a.ln != b.ln) return a.ln < b.ln ? -1 : 1;
	if (a.col != b.col) return a.col < b.col ? -1 : 1;
	return a.check.compare_to(b.check);
}

<*
 Turn the parser's own errors into diagnostics.

 This mapping is the only place a ParseError becomes a Diagnostic, which is
 what lets the parser stay free of c3vet types (docs/DESIGN.md 1.5 rule 2).
*>
fn void collect_parse_errors(DiagnosticList* out, String file, ParseResult* r)
{
	foreach (e : r.errors)
	{
		lexer::Token t = r.toks.tok(e.tok);
		out.push({
			.file      = file,
			.ln        = t.ln,
			.col       = t.col,
			.first_tok = e.tok,
			.last_tok  = e.tok,
			.check     = PARSE_CHECK,
			.msg       = e.msg,
		});
	}
}
