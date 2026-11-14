# c3vet — Design

Implementation contract. Read with `ROADMAP.md` (why) and `CHECKS.md` (what).

Everything in §2–§5 is **frozen in Phase 0 and orchestrator-owned**. Agents
consume these interfaces and do not edit them; see `WORKPLAN.md`.

---

## 1. Layout

Three layers, each depending only on the one below it:

```
c3vet/
  project.json              dependencies: ["lexer"]   (c3l)
  c3l.lock                  pinned lexer v0.1.1
  lib/lexer.c3l/            fetched by c3l — never edited, never committed
  src/
    parser/                 module c3::parser     — STANDALONE, CARVE-OUT UNIT
      ast.c3                node arena, NodeKind, span access      [FROZEN]
      lex.c3                lexer.c3l -> flat Token[] with trivia index
      parse.c3              Parser state, recovery, entry points    [FROZEN]
      parse_type.c3         type grammar
      parse_expr.c3         expression grammar
      parse_stmt.c3         statement grammar
      parse_decl.c3         declaration + top-level grammar
      walk.c3               generic AST visitor
      error.c3              ParseError — the parser's own error type [FROZEN]
      api.c3                parse() / ParseResult — the public surface [FROZEN]
    c3vet/                  module c3vet          — engine library
      scope.c3              T2: per-function scopes, declared types
      flow.c3               T2: statement reachability
      table.c3              T3: declaration table (indexed scope, §5)
      diag.c3               Diagnostic, rendering                   [FROZEN]
      suppress.c3           // c3vet:ignore parsing
      engine.c3             Check interface, tier scheduling        [FROZEN]
      registry.c3           the static check array                  [ORCH]
      config.c3             config file + enable/disable resolution
      checks/
        <one file per check>
    cli/                    module c3vet::cli     — the binary
      main.c3
      args.c3
      files.c3              target resolution, project.json sources
  test/
    parser/                 parser tests — must pass with ONLY src/parser
      invariants.c3         structural invariant checks
      conformance.c3        corpus driver
      shape_*.c3            per-grammar-area node-shape assertions
    harness.c3              testdata runner (engine)
    testdata/<check>.c3     one file per check
  docs/
```

`project.json` carries three targets:

- `c3vet` — the binary: `sources: ["src/parser/**", "src/c3vet/**", "src/cli/**"]`
- `parser` — **static library from `src/parser/**` alone.** This is the
  carve-out guard (§1.5); if it stops building, a reverse dependency has crept
  in.
- test sources: `["test/**"]`, with `test/parser/**` also runnable against the
  `parser` target alone.

---

## 1.5 Carve-out contract (`src/parser/` → `parser.c3l`)

The parser is designed from day one to be liftable into its own `c3l` library.
C3 has no reusable parser; `c3f` built a bespoke token model and `c3c-fuzz`
reached for tree-sitter because none existed. c3vet is the parser's first
consumer, not its owner.

**Five rules. All five are mechanically checked, because "we'll keep it clean"
never survives three agents and six phases.**

1. **Imports.** Files under `src/parser/` may import `std::*` and `c3::lexer`.
   Nothing else — in particular never `c3vet`, `c3vet::cli`, or anything under
   them. The dependency arrow points one way, always.
2. **No borrowed types.** The parser never names `Diagnostic`, `Check`, `Ctx`,
   `Config` or `Unit`. It reports problems as its own `ParseError` (§4);
   `c3vet` maps `ParseError` → `Diagnostic` in `diag.c3`. This is the single
   most likely coupling to appear by accident, which is why `error.c3` is
   frozen.
3. **No globals, no ambient state.** Every entry point takes an `Allocator`.
   No config lookup, no logging, no `getenv`, no process exit, no file I/O —
   the parser is handed a `String` and returns a `ParseResult`.
4. **Self-contained tests.** `test/parser/**` must pass with only
   `src/parser/**` compiled. A parser test may not reference a check.
5. **CI proves it.** Two gates, in every run: `c3c build parser` (builds the
   library target with no `src/c3vet` present) and a grep over `src/parser/`
   for forbidden imports. A green `c3vet` build alone does **not** demonstrate
   separability.

**The public surface** (`api.c3`) is the whole library as far as consumers are
concerned:

```c3
struct ParseResult
{
    TokenList        toks;
    Ast              ast;
    List{ParseError} errors;
    bool             lex_failed;
}

<* Parse C3 source. Never fails: on bad input, `errors` is non-empty and the
   AST contains ERROR_* nodes with valid spans. *>
fn ParseResult parse(Allocator a, String src);
fn void ParseResult.free(&self);
```

Lifting it later is then: copy `src/parser/` + `test/parser/`, add a
`manifest.json` with `"provides": "parser"`, publish, and replace it here with
a `c3l` dependency. No code changes — that is the point of the rules above.

Naming follows `lexer.c3l` → `c3::lexer`, so `parser.c3l` → `c3::parser`.

---

## 2. Tokens

From `lexer.c3l` v0.1.1 (`module c3::lexer`). Its `Token` is already everything
we need:

```c3
struct Token { TokenType type; String text; sz offset; sz len; sz ln, col; }
```

`lex.c3` drains the lexer into a flat array **once** per file:

```c3
struct TokenList
{
    List{Token} all;      // every token, trivia included, in source order
    List{uint}  code;     // indices into .all of non-trivia tokens only
}
```

Trivia is `LINE_COMMENT`, `BLOCK_COMMENT`, `CONTRACT`, `EOL`. **The parser walks
`code` and never sees trivia.** Trivia stays addressable in `all` so that
`suppress.c3` can find `// c3vet:ignore` and checks can reach contracts.

**Contracts are trivia, and that is the whole model.** A `CONTRACT` token
(`<* ... *>`) is never a node in the AST. The parser does not descend into it.
Instead `lex.c3` records, for each declaration's first token, the index of the
`CONTRACT` token immediately preceding it:

```c3
fn uint TokenList.contract_before(&self, uint code_idx);   // NO_TOKEN if none
```

The Phase 4 contract checks (`contract-unknown-param`,
`contract-missing-return`) are the only consumers. They take that token's
lexeme and run `lexer::ContractLexer` over it on demand — the second lexing
mode `lexer.c3l` provides precisely for this. Nothing else parses contract
interiors, and no contract content enters the arena.

Rationale: this is the one place where we deviate from c3f, which must preserve
every byte. A vet tool does not, so the parser gets a clean stream.

Lexing a file with `INVALID_CHAR` is not fatal: record a diagnostic, keep the
tokens produced so far, mark `Unit.lex_failed`, and still run T1 checks on what
parsed.

---

## 3. AST

Flat arena, indices not pointers. One `Ast` per file.

```c3
alias NodeId = uint;
const NodeId NONE = 0;        // index 0 is a reserved sentinel node

struct Node
{
    NodeKind kind;            // ushort
    uint     tok;             // the node's *principal* token (operator, keyword, or name)
    uint     first_tok;       // span start, inclusive, index into TokenList.code
    uint     last_tok;        // span end, inclusive
    NodeId   lhs;
    NodeId   rhs;
}

struct Ast
{
    List{Node}   nodes;       // nodes[0] is the NONE sentinel
    List{NodeId} extra;       // child lists live here
    NodeId       root;
}
```

### The field contract

`lhs` / `rhs` mean different things per kind. **This table is the contract; it
is normative and lives next to the `NodeKind` enum in `ast.c3`.** Every kind
added must add its row in the same commit.

| Kind | `tok` | `lhs` | `rhs` |
|---|---|---|---|
| `BINARY` | the operator | left operand | right operand |
| `UNARY` | the operator | operand | `NONE` |
| `POSTFIX` | `++` / `--` | operand | `NONE` |
| `ASSIGN` | `=` or compound | target | value |
| `TERNARY` | `?` | condition | `extra`: [then, else] via `rhs`=range |
| `ELVIS` / `OPTELSE` | `?:` / `??` | left | right |
| `CALL` | `(` | callee | arg list range |
| `MEMBER` | `.` | object | ident node |
| `SUBSCRIPT` | `[` | object | index |
| `IF` | `if` | condition | `extra`: [then, else-or-NONE] |
| `BLOCK` | `{` | child range start | child count |
| `FN_DECL` | the name | signature | body block |
| ... | | | |

**List-bearing nodes** (`BLOCK`, `CALL` args, parameter lists, `SWITCH` cases,
struct members, initializer lists) store `lhs` = start index into `Ast.extra`
and `rhs` = count. Accessors, never raw indexing:

```c3
fn NodeId[] Ast.children(&self, NodeId n);
fn Node*    Ast.node(&self, NodeId n);
```

### Why spans are stored, not computed

Every node carries `first_tok`/`last_tok` explicitly. ~24 bytes per node is
irrelevant at this corpus size, and in exchange: diagnostics get exact ranges
for free, the span-coverage invariant (§6) becomes checkable, and `--fix`
remains possible later without touching the IR.

### NodeKind taxonomy

Grounded in `grammar.y`. Four families, one enum, with contiguous ranges so that
`is_expr(kind)` etc. are range comparisons:

- **Decl**: `MODULE IMPORT FN_DECL MACRO_DECL ATTRMACRO_DECL STRUCT_DECL
  UNION_DECL BITSTRUCT_DECL ENUM_DECL INTERFACE_DECL TYPEDEF_DECL ALIAS_DECL
  CONST_DECL GLOBAL_DECL FAULTDEF ATTRDEF CONSTDEF CONSTSET CT_INCLUDE
  CT_ASSERT_DECL CT_ECHO_DECL CT_ERROR_DECL CT_EXPAND`
- **Stmt**: `BLOCK VAR_DECL EXPR_STMT RETURN IF WHILE DO FOR FOREACH FOREACH_R
  SWITCH CASE DEFAULT NEXTCASE BREAK CONTINUE DEFER ASSERT ASM_BLOCK EMPTY_STMT
  CT_IF CT_SWITCH CT_FOR CT_FOREACH LABEL ERROR_STMT`
- **Expr**: `BINARY UNARY POSTFIX ASSIGN TERNARY ELVIS OPTELSE CALL SUBSCRIPT
  SLICE MEMBER IDENT PATH PLACEHOLDER INT_LIT REAL_LIT STRING_LIT CHAR_LIT
  BYTES_LIT BOOL_LIT NULL_LIT INIT_LIST CAST LAMBDA TRY_EXPR CATCH_EXPR
  FORCE_UNWRAP RETHROW BUILTIN SPLAT RANGE CT_CALL CT_IDENT_EXPR ERROR_EXPR`
- **Type**: `TYPE_BASE TYPE_NAME TYPE_PTR TYPE_ARRAY TYPE_SLICE TYPE_VEC
  TYPE_OPTIONAL TYPE_GENERIC TYPE_FN TYPE_INFERRED TYPE_EXPR`

### Expression precedence

From `grammar.y`, loosest to tightest. Implement as precedence climbing in
`parse_expr.c3`:

```
assignment   =  +=  -=  *=  /=  %=  <<=  >>=  &=  ^=  |=     (right assoc)
ternary      ?:   ??  (elvis, optelse)                        (right assoc)
or           ||  |||
and          &&  &&&
relational   ==  !=  <  >  <=  >=
additive     +  -
bit          &  |  ^
shift        <<  >>
mult         *  /  %
unary        &  *  +  -  ~  !  --  ++  (prefix)
postfix      call  [ ]  .  ++  --  !  !!  ?
primary      literals, idents, paths, (expr), initializer lists, lambdas
```

Two grammar details that *will* bite and must be handled explicitly:

1. **`grammar.y` duplicates the whole chain as `*_stmt_expr`.** That exists
   solely to stop a `{` at statement start being read as an initializer list.
   Model it as a `no_init_list` flag threaded through expression parsing, not as
   a duplicated function hierarchy.
2. **`lambda_decl` (`fn ... =>`) sits at ternary precedence**, so a lambda is
   legal wherever a ternary is. `TRY`/`CATCH` have their own restricted operand
   grammar (`try_catch_rhs_expr`). Do not hand-wave these.

---

## 4. Parser

Recursive descent, one `Parser` over `TokenList.code`.

```c3
struct Parser
{
    TokenList* toks;
    Ast*       ast;
    uint       pos;           // index into toks.code
    List{ParseError}* errors; // NOT Diagnostic — see §1.5 rule 2
    bool       no_init_list;  // see §3
    uint       depth;         // recursion guard
}
```

The parser's own error type, deliberately minimal — no severity, no check
name, no file path, because the parser does not know about any of those:

```c3
struct ParseError
{
    uint   tok;     // index into TokenList.code
    String msg;
}
```

`c3vet` turns these into `Diagnostic`s, supplying the path and the
`[parse]` check name. A parse error is reported to the user like any other
finding.

### Recovery

Vet runs on code that is being typed. The parser never aborts a file.

- **Statement level:** on an unexpected token, emit one diagnostic, then consume
  until `EOS` (`;`) or a balanced `RBRACE`, and emit an `ERROR_STMT` node whose
  span covers everything skipped.
- **Top level:** sync on the next declaration-start token (`module` `import`
  `fn` `macro` `struct` `union` `enum` `bitstruct` `interface` `typedef`
  `alias` `const` `attrdef` `faultdef` `constset` `static` `extern` `tlocal`)
  at brace depth 0.
- **One diagnostic per recovery event.** Cascades are worse than silence.
- `depth` caps recursion (deeply nested parens in generated code); exceeding it
  is a recovery event, not a crash.

Nodes under an `ERROR_*` subtree are still in the arena with valid spans. Checks
default to `skip_on_error = true` and simply do not run on functions containing
error nodes; a check may opt in if it is robust.

### Compile-time constructs

`$if`, `$switch`, `$for`, `$foreach`, generic parameters, macro bodies and
`asm` blocks are parsed **structurally**: correct kind, correct span,
correct nesting, shallow interior. They must never be skipped as opaque token
runs — an unparsed region silently disables every check around it, which is a
false negative we would never notice. (Contract blocks are **not** in this
list; see §2 — they are trivia, read on demand with `ContractLexer`.)

---

## 5. Engine, diagnostics, suppression

### Check interface  [FROZEN]

```c3
enum Tier : char { SYNTAX, LOCAL, PROJECT }

alias CheckFn = fn void(Ctx* ctx, Unit* unit);

struct Check
{
    String  name;           // kebab-case, stable, user-visible: "self-assign"
    String  doc;            // one line, shown by --list-checks
    Tier    tier;
    bool    default_on;     // set only after a clean corpus FP run
    bool    skip_on_error;  // default true
    CheckFn run;
}
```

```c3
struct Unit                 // one source file
{
    String     path;
    TokenList  toks;
    Ast        ast;
    Scopes*    scopes;      // non-null iff some enabled check is >= LOCAL
    Flow*      flow;        // non-null iff some enabled check is >= LOCAL
    bool       lex_failed;
    bool       has_errors;  // contains ERROR_* nodes
}

struct Ctx
{
    DeclTable* table;       // non-null iff some enabled check is PROJECT
    Config*    config;
    List{Diagnostic}* out;
}
```

`registry.c3` holds a static `Check[]`. The engine takes the max tier over
*enabled* checks and builds only those layers — a run with only T1 checks never
pays for scopes or the project table.

Report helper, so no check formats its own location:

```c3
fn void Ctx.report(&self, Unit* u, NodeId n, String check, String fmt, args...);
```

### Diagnostic  [FROZEN]

```c3
struct Diagnostic
{
    String file;
    sz     ln, col;
    uint   first_tok, last_tok;   // retained for a future --fix; unused in v1
    String check;
    String msg;
}
```

Rendered go-vet style, one line, sorted by file then position:

```
src/parse.c3:42:9: self-assignment of 'count' [self-assign]
```

Exit codes: `0` clean · `1` findings · `2` tool error (bad args, unreadable
file). Findings on stdout, tool errors on stderr — so `c3vet | wc -l` works in
CI.

### Suppression

c3c has none; this is a core part of c3vet's value.

```c3
a = a;                      // c3vet:ignore
a = a;                      // c3vet:ignore[self-assign]
// c3vet:ignore[self-assign]   <- also applies to the next code line
// c3vet:ignore-file[float-equal]
```

Bare `ignore` suppresses every check on that line. Resolved from the trivia
tokens in `TokenList.all`, so it costs nothing extra. `--no-suppress` ignores
all of them for audit runs, and the run summary always reports how many
findings were suppressed — a suppression you forgot about is a bug.

### Target resolution and scoping

```
c3vet                 # current project: project.json "sources"
c3vet src/ file.c3    # explicit paths, dirs walked recursively
c3vet --list-checks
c3vet --enable=x,y --disable=z
c3vet --no-suppress
```

**Indexed scope is not reported scope.** These are two different sets and
conflating them would either break `missing-format-attr` or reproduce c3c's
stdlib flooding:

- **Reported scope** — project sources only (`project.json` `sources`, or the
  explicit CLI paths). **A diagnostic is only ever emitted for a file in this
  set.** Never `lib/`, never `build/`, never dot-directories, never the stdlib.
  This is the direct answer to c3c's flooding.
- **Indexed scope** — reported scope **plus** `lib/*.c3l` dependencies and the
  standard library, parsed declaration-only and used solely to answer questions
  about *declarations*: "does `io::printfn` carry `@format`?", "what does
  `std::math` export?". Required by `missing-format-attr` and `unused-import`,
  which are otherwise reduced to a hardcoded list of known names.

So `table.c3` (§4 T3) indexes the wider set and `Ctx.report` enforces the
narrower one — the filter lives in `report`, not in each check, so a check
cannot leak a stdlib diagnostic by forgetting to guard.

Indexing the stdlib is declaration-only: parse to the end of each signature and
skip function bodies entirely. Keep it off the critical path — it is built once
and only when a `PROJECT`-tier check is enabled.

Config in `project.json` under a `c3vet` key, or `.c3vet` in the project root;
CLI flags win.

---

## 6. Structural invariants

Checked by `test/invariants.c3` on every corpus file. These catch the parser
bugs that plain conformance misses:

1. **Token coverage** — every non-trivia token is inside exactly one leaf
   node's span. A token covered zero times means a dropped construct; twice
   means overlapping spans.
2. **Span nesting** — for every edge, child span ⊆ parent span, and
   `first_tok <= tok <= last_tok`.
3. **Edge validity** — every non-`NONE` `NodeId` is in range; no node is its own
   ancestor; `extra` ranges stay in bounds.
4. **Determinism** — parsing the same bytes twice yields byte-identical arena
   dumps, and running the engine twice yields identical diagnostics.

Invariant 1 is the one that earns its keep: it is what makes "we silently did
not parse `$foreach` bodies" impossible to ship.

---

## 7. Testdata format

`go vet`'s `analysistest` convention. One file per check,
`testdata/<check-name>.c3` (at the project root, not under `test/` -- see the
layout above):

```c3
module testdata_self_assign;

fn void f(int count)
{
    count = count;              // want "self-assignment of 'count'"
    count = count + 1;          // no diagnostic expected
}
```

The harness runs the engine with **only that check enabled** and requires an
exact 1:1 match: every `// want "<regex>"` matches a diagnostic on that line,
and every diagnostic has a corresponding `want`. An unannotated diagnostic fails
the test — that is how we keep false positives from creeping in silently.

Every testdata file must itself compile under `c3c -C`. A check that fires on
code the compiler rejects is out of charter by definition (§1 of the roadmap):
if c3c already errors, c3vet stays quiet.
