---
name: setup-annotation-guard
description: Ban code comments in a repo with an ast-grep rule, allowing only tool directives, wire it into the repo's lint and CI, and remove the comments already there.
disable-model-invocation: true
---

# Setup annotation guard

Install a lint rule in the target repo that fails on any code comment that isn't a tool directive. The code is the documentation: intent goes in names, types, structure, and tests; the reason for a change goes in its commit message. Comments that narrate past decisions are what later agents copy and trust, so none get written.

The target repo is the current working directory, unless a path was passed to this skill. Path passed (blank if none): $ARGUMENTS

The guard is ast-grep, not this skill. Everything an agent is allowed to write lives in the rule files, where a change to it shows up in a diff and gets reviewed. This skill only sets the rule up.

## 0. Preconditions

- The target is a git repo with a clean working tree. Dirty → stop and ask; the cleanup in section 5 must be its own diff.
- The guard isn't installed yet. This skill runs once per repo. `no-comments-*` rules already present → stop, and tell the user the guard is in place; changes to it from here on are edits to its rule files, reviewed like any other diff.
- ast-grep runs as `ast-grep`. Never as `sg`: on Linux that name is the setgroups command.
- The scripts in `${CLAUDE_SKILL_DIR}/scripts/` do every multi-step part of this skill. Run each exactly as shown: they run under bash whatever your shell is, and read and write their state in `<scratchpad>`, so no sha or variable has to be carried from one command to the next. They call `ast-grep` from PATH; with one installed in your scratchpad, start the command with `PATH="<scratchpad>/ast-grep/node_modules/.bin:$PATH"`.
- The inventory needs ast-grep before the user picks how to pin it. Use the one on PATH. None → install one into your scratchpad, outside the repo (`npm install --prefix <scratchpad>/ast-grep @ast-grep/cli@<version>`), and say so in the reply. Prefer 0.39.5, the version this skill's tables were checked against.
- Find the repo's own commands for build, typecheck, lint, and test (package scripts, Makefile, CI config), and write them to `<scratchpad>/checks.txt`, one line each, in this order, `absent` for one the repo doesn't have:

  ```
  build: npm run build
  typecheck: npm run typecheck
  lint: absent
  test: npm test
  ```

  Dependencies not installed (a fresh clone with no `node_modules`, no virtualenv) → install them first with the command CI uses (`npm ci`), or every check fails before and after alike and the comparison proves nothing. It changes no tracked file.

  Then record the baseline section 6 compares against, and `<base>`, the revision the ledger (section 3) refers to, which stays put when the user commits. `<base>` from here on is the sha this saves in `<scratchpad>/base`:

  ```bash
  git rev-parse HEAD > <scratchpad>/base && bash "${CLAUDE_SKILL_DIR}/scripts/checks.sh" <scratchpad>/checks.txt <scratchpad>/before
  ```

  It prints each check's exit status and saves it to `<scratchpad>/before/status.txt`, and each check's output to `<scratchpad>/before/<name>.log`; read the pass/fail counts there. A check that fails now is noted, not fixed.

## 1. Inventory

List the languages in the repo from `git ls-files`. For each, find which node kinds are comments. Verified against ast-grep 0.39.5; on any other version, run the probe below for every language you use, table or not:

| Language | Comment kinds |
| -------- | ------------- |
| TypeScript, Tsx, JavaScript, Go, Python, Bash, Ruby, C, C++, CSS, HTML, YAML | `comment` |
| Rust | `line_comment`, `block_comment` (`///` doc comments are inside `line_comment`) |
| Java | `line_comment`, `block_comment` |
| Kotlin | `line_comment`, `multiline_comment` |

A language not in the table → write a small file with one line comment and one block comment, and count matches for each candidate kind:

```bash
ast-grep scan --inline-rules '{id: probe, language: <lang>, rule: {kind: <kind>}}' --json=stream <file> | wc -l
```

`TypeScript` and `Tsx` are separate ast-grep languages. A repo with `.tsx` files needs both.

Files ast-grep has no grammar for (TOML, Makefile, Dockerfile, …) can't be guarded. Don't write a regex linter for them.

Code embedded in another language is a separate case:

- `<script>` and `<style>` in HTML are guarded. In `.html` files the JavaScript rule reaches `<script>`, the TypeScript rule reaches `<script lang="ts">`, and the CSS rule reaches `<style>`; `-U` cleans them. Write those rules for a repo with HTML even if it has no `.js`, `.ts`, or `.css` files.
- Code inside a string is invisible: a YAML `run: |` block is a YAML string, so the shell comments in it are never seen. The same goes for SQL in string literals. Find them by hand (`git grep -n` for `run: |` and the like) and count them for Ask once. If the user chooses to remove them, they're recorded with the files ast-grep can't parse (below).

Unparseable files and invisible embedded code both go in the reply under Unguarded. Whether their existing comments go is the user's call (Ask once). Run section 2's directive check over them too: unguarded files hold tool directives like any other (`--> statement-breakpoint` in a Drizzle migration, `-- +goose Up`, `# syntax=docker/dockerfile:1`), and removing one breaks the tool. Migrations are better left alone entirely. If the user chooses to remove unguarded comments, extract every one into `<scratchpad>/comments-unguarded.jsonl` right after Ask once, before any file is edited: one object per comment with its file, line, and full text. Section 5 removes each by its text, not its line.

Find any `ast-grep-ignore` already in the repo (`git grep -n -G 'ast-grep[-]ignore'`; `-G` so `grep.patternType` can't change the pattern). It hides comments from every scan, and section 4 bans it everywhere. The ledger (section 3) records each such line and the comments it hid; section 5 deletes it, in ignored paths too.

Markdown is prose, not code: leave it out of the inventory and the counts. Its `#` lines are headings, not comments.

JSON is data, not code: no rule for it, `.json` and JSONC (`tsconfig.json`) alike. Guarding it would mean telling generated JSON, fixtures, and lockfiles apart by judgement. Count its comments with the dump below, language `Json`, kind `comment`; any found go under Unguarded with the unparseable files.

Then dump every comment in the repo, one JSON object per line, and group them by their first few characters:

```bash
ast-grep scan --no-ignore hidden --globs '!.git' --inline-rules '{id: c, language: <lang>, rule: {any: [{kind: <kind>}, …]}}' --json=stream . > <scratchpad>/comments-<lang>.jsonl
```

By default ast-grep skips hidden directories, so `.github/workflows` and the like would never be seen. `--no-ignore hidden` brings them in, and `--globs '!.git'` keeps git's own directory out. `.gitignore` is still honoured. Every `ast-grep scan` in this skill takes the same two flags.

The groups that recur with a fixed prefix are the candidate directives. Everything else is prose. Write down the count of each kind now — line comments, block comments, doc comments (JSDoc, `///`), Python docstrings, each directive group — so the questions below quote real numbers.

Also find what must be skipped entirely: generated files (a `Code generated … DO NOT EDIT.` or `@generated` header), vendored code (`vendor/`, `third_party/`), anything a generator rewrites, and test inputs captured from outside: fixtures, snapshots (`__snapshots__/`, `*.snap`), saved HTML pages, recorded API responses (cassettes, `*.har`), golden files. Changing a captured input changes what the test checks; an HTML fixture's `<script>` is reached by the JavaScript rule and `-U` would rewrite it. All of these keep their comments and go in `ignores`.

So does every submodule, each path `git ls-files -s` lists with mode `160000`: it's another repo, and the scans here would walk into its checkout. Its `<path>/**` goes in every rule's `ignores`, whatever languages it holds; leave its comments out of the counts. `remove.sh` stops before removing anything if a guard rule still reaches one.

## 2. Exceptions

A comment is allowed only if a tool reads it, and only if that tool is configured in this repo: its config is checked in, or lint, CI, or the build runs it. No ruff or flake8 config → no `noqa`. Start from these, and keep only what the inventory found or the repo's tools need:

| Tool | Allowed form |
| ---- | ------------ |
| shell, Python | `#!<shebang>`, first thing in the file |
| Python | `# -*- coding: <encoding> -*-`, at the top of the file (after the shebang if there is one) |
| ruff, flake8 | `# noqa: <CODE>[, <CODE>]` (a bare `# noqa` stays banned) |
| mypy | `# type: ignore[<code>]` (bare stays banned) |
| pyright | `# pyright: ignore[<rule>]` |
| Go | `//go:build <expr>`, `//go:generate <command>`, `//go:embed <pattern>`, `//nolint:<linter>` |
| TypeScript | `// @ts-expect-error`, exactly (`@ts-ignore` stays banned: it never reports when it's no longer needed) |
| TypeScript | `/// <reference types="<pkg>" />`, `/// <reference path="<file>" />`, at the top of the file |
| TypeScript, Babel | `/** @jsxImportSource <pkg> */` |
| Vitest, Jest | `// @vitest-environment <env>`, `/** @jest-environment <env> */` |
| ESLint | `// eslint-disable-next-line <rule>`, `// eslint-disable-line <rule>` (file- and block-wide forms stay banned) |
| Prettier | `// prettier-ignore` |
| bundlers | `/*#__PURE__*/`, `/* @__PURE__ */`, `/* webpackChunkName: "<name>" */`, `/* @vite-ignore */` |
| coverage | `/* istanbul ignore (next|if|else|file) */`, `/* c8 ignore (next|start|stop) */` |
| licensing | `SPDX-License-Identifier: <id>`, only if the repo already uses it |

Each exception is an anchored regex on the comment's full text (`^…$`). A suppression must name what it suppresses, so it can't quietly silence everything around it.

Every `<slot>` above is a place prose could hide: `#!/usr/bin/env do-not-touch-this` and `// eslint-disable-next-line keep-until-v2-ships` are comments wearing a directive's shape. So a slot is never a pattern like `[\w-]+`. It is an alternation of the exact values the inventory found in this repo: `(utf-8)`, `(/usr/bin/env python3|/bin/bash -e)`, `(no-console|no-unused-vars)`. A new value later means editing the rule file, which is a reviewed diff. The one exception is a slot whose format can't hold words, like a ruff code `[A-Z]+[0-9]+`; that may stay a pattern. `@ts-expect-error` accepts a description after it, so its regex ends right after the directive. An exception that only means something in one place is bound to its shape and, as far as ast-grep can see, to that place (section 3), or `#! anything` on line 40 is a free comment. Turn on the tool's own check for stale suppressions where it has one and lint or CI already runs the tool: ruff `RUF100`, ESLint `--report-unused-disable-directives`, mypy `warn_unused_ignores`. Don't wire a tool into lint just to get its check.

`ast-grep-ignore` is never an exception. A comment that starts on a file's first line and contains it anywhere, even inside a multi-line block comment, followed by a blank line, silences every rule for the whole file, including itself, and the scan reports nothing. Telling that apart from a string or a later line takes a parser, and the parser is what's being silenced. So section 4 bans the token from the repo outright, wherever it appears. No code needs it.

### Ask once

Batch these into one AskUserQuestion call, after the inventory and before writing rules. It takes four questions at most, and there are four here. Skip a question the inventory already answers: no unguarded comments, no unknown directives. Python docstrings and doc comments are one question, not two. Still more than four → don't ask about pinning; pin an exact version in CI only, at the version the inventory used, and say so in the reply.

- **Docstrings and doc comments.** Python docstrings are strings, not comments, so `kind: comment` misses them. JSDoc, rustdoc `///`, and Go doc comments are comments, and the rule removes them. Ban both by default. The cost: editors lose the hover text on those functions. Keep them only if the repo builds API docs from them (Sphinx, mkdocstrings, pdoc, TypeDoc, rustdoc config present) or the user wants the hover text; then add an exception for the doc-comment form, limited to the paths the user names.
- **Unguarded comments.** Show the count by file type from section 1: unparseable files, and code embedded in strings. Ask whether to remove them once by hand or leave them. Nothing will keep them out later either way. Config files often hold the repo's most useful comments; say so if that's what you found.
- **Directives the inventory found that aren't in the table above.** Show each, with a count and one example, and ask which a tool actually reads.

Not a question: a directive in the table whose tool isn't configured in this repo (`eslint-disable-next-line` with no ESLint). Section 2 already decides it: it goes with the other comments. List each such group in the reply.
- **How to pin ast-grep** in this repo: a dev dependency (`@ast-grep/cli` in npm, `ast-grep-cli` in pip), or a pinned install in CI only. Pin an exact version; node kind names can change between releases. Write the pin into the manifest yourself, then run the plain install (`npm install`), which leaves a hand-edited manifest as written and only updates the lockfile; `npm install -D -E <pkg>` reflows the whole `package.json`. In `package.json`: `"@ast-grep/cli": "<version>"` in `devDependencies`, in alphabetical order, as npm keeps it; no `devDependencies` → add it as the last key. The manifest's diff is that one line, or that one block. A version other than the one used for the inventory → re-run section 1's probe on it before writing rules.

## 3. Write the rules

At the repo root:

```
sgconfig.yml
rules/no-comments-<lang>.yml
rule-tests/no-comments-<lang>-test.yml
```

If the repo already has an `sgconfig.yml`, add to its `ruleDirs` and `testConfigs` instead.

`sgconfig.yml`:

```yaml
ruleDirs: [rules]
testConfigs:
  - testDir: rule-tests
```

One rule per language:

```yaml
id: no-comments-<lang>
language: <Lang>
severity: error
message: Comments aren't allowed here. Say it in code.
note: |
  Rename or extract a function or variable so the name says it.
  Put a constraint in a type. Put a behaviour in a test name.
  Put the reason for a change in the commit message.
  Tool directives allowed in this repo are listed in rules/no-comments-<lang>.yml.
ignores:
  - <generated and vendored paths from section 1>
rule:
  any:
    - kind: <comment kind>
  not:
    any:
      - regex: '^<exception>$'
fix: ''
```

`ignores` applies only to the rule it's written in. A path goes in every rule that reaches files there, and only those: a rule reaches its own language's files, and the HTML, JavaScript, TypeScript, and CSS rules all reach `.html` files (section 1). So an `.html` fixture directory goes in all four of those rules, if the repo has them; a Python rule never needs it.

`language:` is spelled as the tables in this skill spell it (`CSS`, `YAML`, `C++`). A language with no exceptions drops the `not:` block. The rule files hold no comments of their own. They live in the repo, and an example comment there is the first thing the next agent copies.

The HTML rule always has one exception. Inside `<textarea>`, `<title>`, and the other elements whose content HTML reads as text, `<!-- … -->` is text, not a comment, though the parser reports it as one; deleting it deletes page content. In SVG and MathML those names are ordinary elements, so a comment there stays banned:

```yaml
      - inside: { kind: element, stopBy: end, has: { kind: start_tag, has: { kind: tag_name, regex: '^(?i:textarea|title|xmp|iframe|noembed|noframes|noscript|plaintext)$' } }, not: { inside: { kind: element, stopBy: end, has: { kind: start_tag, has: { kind: tag_name, regex: '^(?i:svg|math)$' } } } } }
```

Position-bound exceptions go in the same `not: any:` list. They name the file's root node, which differs by language: `module` for Python; `program` for TypeScript, Tsx, JavaScript, Bash, and Ruby; `source_file` for Go and Rust. Another language → probe it the way section 1 probes comment kinds. The Python forms:

```yaml
- all:
    - regex: '^#!(/usr/bin/env python3|/bin/bash -e)$'
    - inside: { kind: module, stopBy: neighbor }
    - not: { follows: { regex: '[\s\S]' } }
- all:
    - regex: '^# -\*- coding: (utf-8) -\*-$'
    - inside: { kind: module, stopBy: neighbor }
    - not: { follows: { not: { regex: '^#!' }, stopBy: end } }
```

TypeScript `/// <reference>` lines at the top of the file, any number of them in a row:

```yaml
- all:
    - regex: '^/// <reference types="(vite/client|vite-plugin-pwa/client)" />$'
    - inside: { kind: program, stopBy: neighbor }
    - not:
        follows:
          not: { regex: '^/// <reference types="(vite/client|vite-plugin-pwa/client)" />$' }
          stopBy: end
```

Every node before it must be another listed reference, so the second and third pass and one after code doesn't. Keep the two alternations identical.

The alternations are examples; use the exact shebangs, encodings, and references the inventory found. `stopBy: neighbor` is `inside`'s default, written out because it's what makes this work: the comment's direct parent must be the file itself. With `stopBy: end`, a comment at any depth would pass. The first allows a listed shebang only when no other node precedes it. The second allows a listed coding line only at the top level, with nothing but a shebang before it.

ast-grep sees nodes, not blank lines or indentation, and its `range` rule needs an exact end. So a listed shebang or coding line after blank lines still passes. It can only be one of the repo's own known values, so it carries nothing new; the position checks catch the common case, a directive after real code.

When Python docstrings are banned, they get their own rule, `no-docstrings-python`, with the same `severity`, `message`, `note`, and `ignores`, and no `fix` (section 5 says why):

```yaml
utils:
  string-literal:
    any:
      - kind: string
        not: { has: { kind: string_start, regex: '^[a-zA-Z]*[fFtTbB]' } }
      - kind: concatenated_string
        not: { has: { kind: string_start, regex: '^[a-zA-Z]*[fFtTbB]', stopBy: end } }
      - kind: parenthesized_expression
        has: { matches: string-literal }
rule:
  kind: expression_statement
  has: { matches: string-literal }
```

This matches what Python itself takes as a docstring: a plain string statement, implicitly concatenated (`"a" "b"`) or parenthesized (`("a")`). f-strings, t-strings, and byte strings are left alone, with or without `{…}`: Python never takes one as a docstring, and an f-string runs code. The same shapes elsewhere in a body do nothing at runtime and are matched too.

`severity: error` makes `ast-grep scan` exit 1 on a match, so it can gate lint and CI. The `message` and `note` are what the next agent reads when it writes a comment, so they say what to do instead.

Every rule gets a test file, built from this table and nothing else, so two runs on the same repo write the same file. `<s>` is the statement column. A language section 1 probed because it isn't here gets a row of the same shape: its shortest top-level statement, a string holding its comment characters, and one sample of each comment kind the probe found. Give that row in the reply.

| Language | `<s>` | String | Line | Block | Doc |
| -------- | ----- | ------ | ---- | ----- | --- |
| TypeScript, Tsx, JavaScript | `const a = 1;` | `const s = "// x /* y */";` | `// line` | `/* block */` | `/** doc */` |
| Go | `var a = 1` | `var s = "// x /* y */"` | `// line` | `/* block */` | |
| C, C++ | `int a = 1;` | `const char *s = "// x /* y */";` | `// line` | `/* block */` | |
| Java | `class A {}` | `class A { String s = "// x /* y */"; }` | `// line` | `/* block */` | `/** doc */` |
| Kotlin | `val a = 1` | `val s = "// x /* y */"` | `// line` | `/* block */` | `/** doc */` |
| Rust | `const A: i32 = 1;` | `const S: &str = "// x /* y */";` | `// line` | `/* block */` | `/// doc` |
| Python, Ruby | `a = 1` | `s = "# x"` | `# line` | | |
| Bash | `echo a` | `echo "# x"` | `# line` | | |
| YAML | `a: 1` | `a: "# x"` | `# line` | | |
| CSS | `a { color: red; }` | `a { content: "/* x */"; }` | | `/* block */` | |
| HTML | `<p>a</p>` | `<p>a -- b</p>` | | `<!-- block -->` | |

In this order, skipping an empty cell:

- `valid`: the string; then each exception, in section 2's table order, once per listed value, on the line before `<s>`. An exception that allows a run (the TypeScript references) and lists two or more values also gets all of them in a row; with one value, that case would repeat the one before, so it's left out. Doc comments kept (Ask once) → the doc case goes here instead of in `invalid`. HTML also gets `<textarea><!-- x --></textarea>`, right after the string.
- `invalid`: the line comment, then `<s>`; `<s>` and the line comment on one line; the block comment and `<s>` on one line; the doc comment, then `<s>`. Then, per exception: its slot holding `x-keep-this`; a position-bound one after `<s>`; each banned variant section 2 names for its tool (`# noqa`, `@ts-ignore`, `eslint-disable` without a rule).

Write every case as a `|` block scalar. Unquoted, `: ` makes YAML read a case as a map and `#` starts a YAML comment. `ast-grep-ignore` stays out: section 4 bans it everywhere, test files included. The docstring rule's test is fixed:

```yaml
id: no-docstrings-python
valid:
  - |
    s = "x"
  - |
    f"{s}"
invalid:
  - |
    """doc"""
  - |
    def f():
        """doc"""
        return 1
```

```bash
ast-grep test --skip-snapshot-tests
```

Then record every comment the cleanup will remove:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/ledger.sh" <scratchpad>
```

It scans a worktree of `<base>`, not the working tree, so every position is `<base>`'s whatever this setup has edited, with the repo's own `sgconfig.yml`, so its rules and settings (`languageGlobs` and the like) apply as they will in cleanup. `--filter` keeps it to the guard's rules; a repo that already had ast-grep rules keeps their matches out. Anything but `ledger exit 0` is a failure: stop, and don't remove a comment the ledger hasn't recorded.

This is the ledger: `removed-comments.jsonl`, one object per match, with its file, position, and full text, and `suppressions.txt`, each `ast-grep-ignore` line. The script breaks every `ast-grep-ignore` in its copy, so the comments it hid are recorded; its own row reads `ast-grep_ignore`. With `comments-unguarded.jsonl` (section 1), it's what section 8 works from.

## 4. Wire it in

Add to the repo's existing lint command (package script, Makefile target, or whatever CI and the repo's CLAUDE.md or AGENTS.md tell agents to run), so the check runs wherever lint already runs:

```bash
ast-grep test --skip-snapshot-tests && ast-grep scan --no-ignore hidden --globs '!.git' && ! { git grep -n --untracked -G 'ast-grep[-]ignore' 2>&1 || true; } | grep .
```

The scan flags are the ones from section 1: without them, comments in `.github/` and other hidden directories pass. The last part fails lint when `ast-grep-ignore` appears anywhere in the repo, comment or string, any line, any directory. Anything narrower is a way around it. Four details keep it honest:

- `--untracked`: plain `git grep` searches only tracked files, so a new file an agent hasn't staged yet would slip past. Files the repo's `.gitignore` excludes stay out, as they do for `ast-grep scan`.
- `-G` makes the pattern a basic regex whatever the user's `grep.patternType` says; with `fixed`, `[-]` would be taken literally and match nothing.
- `2>&1 || true; } | grep .` fails lint on any output, a match or git's own error, so a search that fails can't pass as one that found nothing. `|| true` keeps git's exit status out of the pipeline, so it holds with or without `pipefail`.
- `[-]` matches the same text, but the command's own text doesn't contain `ast-grep-ignore`, so the Makefile or package.json holding it doesn't fail its own check.

Paste it into the lint target as is. It has no `$`, double quotes, or backslashes, so it needs no escaping in a Makefile recipe or a package.json script.

No lint command in the repo → create one where the repo keeps its commands, holding just this: a `lint` script as the last entry of `package.json`'s `scripts`, or a `lint` target at the end of the Makefile. If CI doesn't run that lint command, add a step that does, right after the step that installs dependencies: it's the fastest check, so it fails first. Then update the docs that list the repo's development commands (README, CONTRIBUTING): a list of "the checks CI runs" is now one short. Add the lint command as the list's last line, in the list's own format; if its lines carry comments, the comment is `# no code comments (ast-grep)`. If ast-grep is pinned in CI only, install it in a step before lint, after the setup step for its package manager (`actions/setup-node` for npm, `actions/setup-python` for pip); add that setup step if the workflow lacks it. If no agent instruction file in the repo tells agents to run lint before finishing, add this line, with the repo's lint command: ``Run `npm run lint` before finishing a task.`` Claude Code reads `CLAUDE.md`; Codex reads `AGENTS.md`. Add the line to whichever exists. Neither exists → create both, each with the same line. Not a symlink: a Windows clone without `core.symlinks` checks a symlink out as a text file holding the target's name, and Codex reads that instead. Only one exists → add the line there, and say in the reply which harness won't see it. Don't add hooks.

## 5. Remove the existing comments

The ledger from section 3 holds every comment this removes, so nothing is read or sorted here. What the comments knew is section 8's business, after the reply.

Delete each `ast-grep-ignore` listed in `<scratchpad>/suppressions.txt` (section 3), with its line if nothing else is on it. Until it's gone, the comments it hides are invisible to `-U` too.

Then remove the comments:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/remove.sh" <scratchpad>
```

It first records a snapshot of the working tree in `<scratchpad>/snap` (`git stash create`, which doesn't touch the tree, the index, or the stash list; `HEAD` when the tree is clean). Section 4's edits are in it, so nothing below mistakes them for comment removal. New untracked files, like the rule files, aren't; they hold no comments.

Each removal is a pair: a scan with `--json=stream` records exactly what the same scan with `-U` then deletes. One rule per pair, each guard rule in `rules/` by its id: when several rules fix the same file (an HTML file's comment, `<script>`, and `<style>`), one `-U` keeps only one rule's fixes, and filtering by id keeps any other rule's fixes out. The fix deletes the comment text only. Then the empty `{}` that `{/* … */}` leaves in JSX: only an expression container with nothing in it, so `const o = {/* x */}` keeps its `{}`, and only in the files the removal changed, which keeps it out of fixtures. Then `tidy.py` on those records.

It touches only the lines the recorded removals cut, the same way in every language: it drops a line a removal left blank, strips the whitespace a removal left at a line's end, and merges the blank lines around a dropped one. Everything else is kept byte for byte. A file that isn't the snapshot minus those removals is skipped and named; find what changed it before going on. Exit 3 names each line to fix by hand: one where a removal joined code on either side (`return/**/1` is now `return1`) or took a line break from between code (`return /*⏎*/ 1`, where the break ended the statement), since what the comment stood for depends on the language; and one a removal left ending in a backslash, which now continues onto the next line (`#define X \/* note */`). HTML comment cuts in a file with a `<pre>` are left as `-U` made them, since in `<pre>` whitespace is content. Run the repo's formatter after tidy.py, if the repo has one.

`-U` doesn't touch docstrings, because `no-docstrings-python` has no `fix`: removing one can leave a function or class with an empty body, which is a syntax error. Remove each by hand, adding `...` only where the body would otherwise be empty.

Unguarded comments the user chose to remove (Ask once): remove them by hand now. Find each by its text from `comments-unguarded.jsonl`, not by its recorded line.

## 6. Verify

All must hold. Report each with its evidence:

- Build, typecheck, lint, and test give the same results as the section 0 baseline. If section 4 created the lint command, the `lint:` line of `<scratchpad>/checks.txt` now reads `lint: <that command>` (`lint: npm run lint`) instead of `lint: absent`; edit that line, nothing else. Then:

  ```bash
  bash "${CLAUDE_SKILL_DIR}/scripts/checks.sh" <scratchpad>/checks.txt <scratchpad>/after
  ```

  Compare `status.txt` and each log's pass/fail counts with `<scratchpad>/before`. A difference means the cleanup changed behaviour. Find the file at the failing spot and diff it against the sha in `<scratchpad>/snap`. A removed directive → add it to the exceptions, restore it, and re-run. Code the removal changed → put it back as it was, minus the comment, and re-run. A lint command this skill created has no baseline; report it as absent before, passing after.
- `ast-grep test --skip-snapshot-tests` passes.
- The full lint command from section 4 passes on the cleaned repo.
- The guard catches the file-level bypass: put a comment containing `ast-grep-ignore`, a blank line, and another comment in a new, unstaged file at the repo root, `annotation-guard-probe.<ext>`, `<ext>` the extension of the language of the first guard rule file in name order, and run the repo's lint target (not the bare command). An exit code alone proves nothing; it could fail for another reason. It must fail with `git grep` printing that file's line. Then delete the `ast-grep-ignore` line from the same file and run it again: now the scan must report the other comment. Delete the file.
- Rule tests check one language at a time, so they can't show HTML being reached. If the repo has HTML: put a comment in `<script>` and one in `<style>` in a new file at the repo root, `annotation-guard-probe.html`, run the lint target, confirm the scan reports both, and delete the file.

A check that can't run → say so and name what's missing. Don't call the setup done.

## 7. Reply

The skill's own version: the installer records the commit it installed on the first line of `.jackey8616-skills`, in the directory above this skill (`# jackey8616/skills @ <sha>`). No such file (a hand-linked checkout) → `git -C "${CLAUDE_SKILL_DIR}" rev-parse --short HEAD`. Neither → say "unknown".

Don't commit. Leave everything in the working tree, and recommend two commits: the cleanup (section 5) first, then the guard (sections 3–4). In that order every commit passes lint; the guard alone would fail on the comments still there. Two things to tell the user with it:

- A file changed by both, usually the CI workflow (comments gone, lint step added), needs its hunks split. Interactively, `git add -p`. Without a terminal: take the guard's lines out of the file, stage it with the cleanup and commit, put the lines back, then stage and commit the guard.
- The cleanup commit belongs in `.git-blame-ignore-revs` only if it survives merging. A squash merge folds both commits into one, and ignoring that hides the guard too. Squash-only repo → merge this one with a rebase or merge commit, or skip `.git-blame-ignore-revs`.

```
## Annotation guard — <repo>
setup-annotation-guard @ <version>
ast-grep <version>, pinned via <how>

## Rules
| Language | Comment kinds | Exceptions | Ignored paths |
| -------- | ------------- | ---------- | ------------- |

## Wired into
- `<file>` — <command or CI step>

## Cleanup
<n> comments removed across <m> files. tidy.py, then formatter: <command, or "none">.
Ledger: <absolute path to removed-comments.jsonl>, <n> rows; plus comments-unguarded.jsonl, <n> rows, and suppressions.txt, <n> lines, if any. Base: <base sha>.

## Unguarded
- <file type or embedded code> — <count> files, <count> comments — <removed by hand | left>

## Directives removed, tool not configured
- <directive> — <count> — <tool missing>

## Verification
| Check | Before | After |
| ----- | ------ | ----- |
```

End by offering to go through what the removed comments knew (section 8). The ledger is in your scratchpad, which goes with this session; say so, so the user can copy it out if they'll pick it up elsewhere.

## 8. After the reply: what the comments knew

The setup is done; this part is a conversation. Some removed comments held facts the code doesn't: an external constraint, a unit, a known bug. Where those go is the user's call, so don't decide it, and don't start until the user says to. What this section fixes is how the ledger is sorted and in what order it's put to the user.

Read each row in context from `git show <base>:<path>`: the comments are gone from the working tree, and `HEAD` moves once the user commits. Check what it says against the code as it is now, then sort it into one category:

| Category | What it is |
| -------- | ---------- |
| `stale-doc` | Not a row: a doc the code contradicts or doesn't follow, found while reading. Keyed by the doc's `path:line`, once however many rows point at it. |
| `prose` | Why the code is this way, or domain context, that a reader can't get from the code. |
| `external` | A fact about something outside the repo (a platform, a vendor, a plan limit) that the code is consistent with but can't prove. |
| `code` | A name, a constant, a type, or a test would say it. |
| `already-said` | The code or a test says it now. |
| `restates` | Says only what the line below says. |
| `stale` | No longer true. |

Put them to the user in this order, one group at a time: stale docs; prose, grouped by the doc it would go in; external; code. `already-said`, `restates`, and `stale` are only a count, unless the user asks for them. Keep each fact next to its verbatim comment, so a summary can't drift from it.

Hundreds of rows → offer to split them by file across subagents. Each returns one row per comment, with its verbatim text; check that every ledger row came back exactly once.

When the user has a doc written:

- Every sentence traces to a removed comment or to code.
- Add nothing the source doesn't say. "Old URLs redirect to new ones" stays that; "via a Cloudflare rule" is a guess unless the repo says so.
- An `external` fact goes in only as the user confirms it. No "to confirm" markers in the docs.
- It's a third commit, after the two above.
