<*
 Whether an expression's value is temp-allocator-derived.

 Used by `temp-escapes-fn`, `temp-escapes-pool`, `temp-escapes-struct`,
 `temp-wrong-free` and `temp-to-global`. Purely syntactic: no type
 resolution, no alias analysis. A call counts as temp-origin when either:

   - its callee's final name is one of `mem`'s seven temp-allocation
     macros (`talloc`, `talloc_array`, `talloc_with_padding`, `tcalloc`,
     `tmalloc`, `tnew`, `trealloc`), or one of the standard library's own
     "temporary-allocating variant of X" convenience wrappers (free
     function, bare, qualified, or called as a method -- e.g.
     `string::tformat(...)`, `path::tnew(...)`, `s.tconcat(...)`,
     `map.tkeys()`) -- these never take an allocator argument, so the
     only signal is the name; or
   - any of its arguments is literally the identifier `tmem` (bare or
     qualified), the well-known alias for the current temp allocator
     (`x.init(tmem)`, `alloc::new(tmem, Type)`, `path::ls(tmem, ...)`).

 Not detected: a project's own bespoke `t`-prefixed convenience wrapper
 that hardcodes the temp allocator internally without taking one as an
 argument is not recognized unless its name happens to match one of the
 standard library names above -- there is no way to tell, syntactically,
 that an arbitrary name is such a wrapper.
*>
module c3vet;

import c3::parser;

<* The `mem` names that always allocate from the current temp allocator, regardless of arguments. *>
fn bool is_mem_temp_alloc_name(String name) @local
{
	switch (name)
	{
		case "talloc":
		case "talloc_array":
		case "talloc_with_padding":
		case "tcalloc":
		case "tmalloc":
		case "tnew":
		case "trealloc":
			return true;
		default:
			return false;
	}
}

<*
 Standard library convenience wrappers documented as "temporary-allocating
 variant of X" (or equivalent): they hardcode the current temp allocator
 internally and never take one as an argument, so like the `mem` names
 above, the only syntactic signal is the name. Collected from
 `std::core::string`, `std::core::dstring`, `std::io::path`, `std::os::env`,
 `std::net::url`, `std::net::url_encoding`, `std::encoding::hex/base32/
 base64/ini/regex`, `std::crypto::aes128/192/256`, and the collection
 modules' `tkeys`/`tvalues`/`tset_union`/`tintersection`/`tdifference`/
 `tsymmetric_difference`/`tcopy_pop`. Matched by bare name only, the same
 as `is_mem_temp_alloc_name` -- a project-defined function or method that
 happens to share one of these names is indistinguishable from the
 standard library one.
*>
fn bool is_temp_wrapper_name(String name) @local
{
	switch (name)
	{
		case "tformat":
		case "tformat_zstr":
		case "tjoin":
		case "tconcat":
		case "tcopy":
		case "tsplit":
		case "zstr_tcopy":
		case "to_temp_utf16":
		case "to_temp_utf32":
		case "to_temp_wstring":
		case "to_tarray":
		case "tfrom_wstring":
		case "tfrom_struct":
		case "tfrom_utf16":
		case "tget_var":
		case "tcwd":
		case "tparse":
		case "tencode":
		case "tdecode":
		case "tescape":
		case "tencrypt":
		case "tdecrypt":
		case "tkeys":
		case "tvalues":
		case "tset_union":
		case "tintersection":
		case "tdifference":
		case "tsymmetric_difference":
		case "tcopy_pop":
		case "texec":
		case "tfind_all":
		case "treplace":
		case "treplace_fn":
		case "tread_row":
			return true;
		default:
			return false;
	}
}

<*
 The final name of a call's callee: the identifier itself for `IDENT`,
 the last segment for `PATH`, or the member name for a `MEMBER_ACCESS`
 (method call) -- `""` for anything else (e.g. a call through a function
 pointer or a parenthesized expression).
*>
fn String callee_name(Ast* ast, TokenList* toks, NodeId callee) @local
{
	if (callee == parser::NONE) return "";
	Node* n = ast.node(callee);
	switch (n.kind)
	{
		case NodeKind.IDENT:
			return toks.text_at(n.tok);
		case NodeKind.PATH:
			return toks.text_at(n.last_tok);
		case NodeKind.MEMBER_ACCESS:
			return callee_name(ast, toks, n.rhs);
		default:
			return "";
	}
}

<* True when `id` (an `IDENT` or `PATH`) spells exactly `tmem` in its final segment. *>
fn bool is_tmem_name(Ast* ast, TokenList* toks, NodeId id) @local
{
	if (id == parser::NONE) return false;
	NodeKind k = ast.kind(id);
	if (k != NodeKind.IDENT && k != NodeKind.PATH) return false;
	return toks.text_at(ast.node(id).last_tok) == "tmem";
}

<*
 True when `call_id` (a `CALL` node) allocates from the current temp
 allocator (see the module doc comment).
*>
fn bool is_temp_origin_call(Ast* ast, TokenList* toks, NodeId call_id)
{
	if (call_id == parser::NONE || ast.kind(call_id) != NodeKind.CALL) return false;
	NodeId[] kids = ast.children(call_id);
	if (!kids.len) return false;
	NodeId callee = kids[0];
	String name = callee_name(ast, toks, callee);
	if (name != "" && (is_mem_temp_alloc_name(name) || is_temp_wrapper_name(name))) return true;
	foreach (arg : kids[1..]) if (is_tmem_name(ast, toks, arg)) return true;
	return false;
}

<*
 True when `init` (a `VAR_DECL`'s `rhs`, or any expression) is temp-origin:
 either directly a qualifying `CALL`, or a `CALL` wrapped in at most one
 `CAST` (`(int*)mem::talloc(int)`). Anything deeper is not tracked.
*>
fn bool is_temp_origin_init(Ast* ast, TokenList* toks, NodeId init)
{
	if (init == parser::NONE) return false;
	Node* n = ast.node(init);
	if (n.kind == NodeKind.CAST) return is_temp_origin_call(ast, toks, n.rhs);
	return is_temp_origin_call(ast, toks, init);
}
