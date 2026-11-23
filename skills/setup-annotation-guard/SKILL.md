---
name: setup-annotation-guard
description: Ban code comments in a repo with an ast-grep rule, allowing only tool directives, wire it into the repo's lint and CI, and remove the comments already there.
disable-model-invocation: true
---

# Setup annotation guard

Install a lint rule in the target repo that fails on any code comment that isn't a tool directive. The code is the documentation: intent goes in names, types, structure, and tests; the reason for a change goes in its commit message. Comments that narrate past decisions are what later agents copy and trust, so none get written.

Target repo: $ARGUMENTS

No path above → the current working directory.

The guard is ast-grep, not this skill. Everything an agent is allowed to write lives in the rule files, where a change to it shows up in a diff and gets reviewed. This skill only sets the rule up.

## 0. Preconditions

- The target is a git repo with a clean working tree. Dirty → stop and ask; the cleanup in section 5 must be its own diff.
- ast-grep runs as `ast-grep`. Never as `sg`: on Linux that name is the setgroups command.
- The inventory needs ast-grep before the user picks how to pin it. Use the one on PATH. None → install one into your scratchpad, outside the repo (`npm install --prefix <scratchpad>/ast-grep @ast-grep/cli@<version>`), and say so in the reply. Prefer 0.39.5, the version this skill's tables were checked against.
- Find the repo's own commands for build, typecheck, lint, and test (package scripts, Makefile, CI config). Run all four now and record each command, exit status, and pass/fail counts. This is the baseline section 6 compares against. A command that fails now is noted, not fixed.

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

- `<script>` and `<style>` in HTML are guarded. A JavaScript or CSS rule reaches them in `.html` files, and `-U` cleans them. Write those rules for a repo with HTML even if it has no `.js` or `.css` files.
- Code inside a string is invisible: a YAML `run: |` block is a YAML string, so the shell comments in it are never seen. The same goes for Markdown code fences and SQL in string literals. Find them by hand (`git grep -n` for `run: |` and the like).

Unparseable files and invisible embedded code both go in the reply under Unguarded. Whether their existing comments go is the user's call (Ask once).

Then dump every comment in the repo, one JSON object per line, and group them by their first few characters:

```bash
ast-grep scan --no-ignore hidden --globs '!.git' --inline-rules '{id: c, language: <lang>, rule: {any: [{kind: <kind>}, …]}}' --json=stream . > <scratchpad>/comments-<lang>.jsonl
```

By default ast-grep skips hidden directories, so `.github/workflows` and the like would never be seen. `--no-ignore hidden` brings them in, and `--globs '!.git'` keeps git's own directory out. `.gitignore` is still honoured. Every `ast-grep scan` in this skill takes the same two flags.

The groups that recur with a fixed prefix are the candidate directives. Everything else is prose.

Also find what must be skipped entirely: generated files (a `Code generated … DO NOT EDIT.` or `@generated` header), vendored code (`vendor/`, `third_party/`), and anything a generator rewrites. These keep their comments and go in the rule's `ignores`.

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

Batch these into one question for the user, after the inventory and before writing rules:

- **Docstrings and doc comments.** Python docstrings are strings, not comments, so `kind: comment` misses them. JSDoc, rustdoc `///`, and Go doc comments are comments, and the rule removes them. Ban both by default. The cost: editors lose the hover text on those functions. Keep them only if the repo builds API docs from them (Sphinx, mkdocstrings, pdoc, TypeDoc, rustdoc config present) or the user wants the hover text; then add an exception for the doc-comment form, limited to the paths the user names.
- **Unguarded comments.** Show the count by file type from section 1: unparseable files, and code embedded in strings. Ask whether to remove them once by hand or leave them. Nothing will keep them out later either way. Config files often hold the repo's most useful comments; say so if that's what you found.
- **Directives the inventory found that aren't in the table above.** Show each, with a count and one example, and ask which a tool actually reads.
- **How to pin ast-grep** in this repo: a dev dependency (`@ast-grep/cli` in npm, `ast-grep-cli` in pip), or a pinned install in CI only. Pin an exact version; node kind names can change between releases. A version other than the one used for the inventory → re-run section 1's probe on it before writing rules.

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

A language with no exceptions drops the `not:` block. The rule files hold no comments of their own. They live in the repo, and an example comment there is the first thing the next agent copies.

Position-bound exceptions go in the same `not: any:` list. The Python forms; for Bash use `kind: program` in place of `module`:

```yaml
- all:
    - regex: '^#!(/usr/bin/env python3|/bin/bash -e)$'
    - inside: { kind: module }
    - not: { follows: { regex: '[\s\S]' } }
- all:
    - regex: '^# -\*- coding: (utf-8) -\*-$'
    - inside: { kind: module }
    - not: { follows: { not: { regex: '^#!' }, stopBy: end } }
```

The alternations are examples; use the exact shebangs and encodings the inventory found. The first allows a listed shebang only when no other node precedes it. The second allows a listed coding line only at the top level, with nothing but a shebang before it.

ast-grep sees nodes, not blank lines or indentation, and its `range` rule needs an exact end. So a listed shebang or coding line after blank lines still passes. It can only be one of the repo's own known values, so it carries nothing new; the position checks catch the common case, a directive after real code.

When Python docstrings are banned, they get their own rule, `no-docstrings-python`, with the same `severity`, `message`, `note`, and `ignores`, and no `fix` (section 5 says why):

```yaml
utils:
  string-literal:
    any:
      - kind: string
        not: { has: { kind: interpolation, stopBy: end } }
      - kind: concatenated_string
        not: { has: { kind: interpolation, stopBy: end } }
      - kind: parenthesized_expression
        has: { matches: string-literal }
rule:
  kind: expression_statement
  has: { matches: string-literal }
```

This matches what Python itself takes as a docstring: a plain string statement, implicitly concatenated (`"a" "b"`) or parenthesized (`("a")`). An f-string with a `{…}` runs code, so it's left alone; Python never takes one as a docstring anyway. The same shapes elsewhere in a body do nothing at runtime and are matched too.

`severity: error` makes `ast-grep scan` exit 1 on a match, so it can gate lint and CI. The `message` and `note` are what the next agent reads when it writes a comment, so they say what to do instead.

Every rule gets a test file. `valid` holds each allowed exception and a string containing comment characters (`"// x"`, `"# x"`). `invalid` holds a line comment, a trailing comment, a block comment, a doc comment, and each banned variant of each exception (`# noqa`, `@ts-ignore`, `eslint-disable` without a rule). Leave `ast-grep-ignore` out of the fixtures too: section 4 bans it everywhere, test files included. Write multi-line cases as `|` block scalars; `\n` inside single quotes stays a literal backslash and n. HTML is the exception to the comment-characters case: its grammar parses `<!--` inside an attribute value as a comment, so leave that case out of an HTML rule's `valid`.

```bash
ast-grep test --skip-snapshot-tests
```

## 4. Wire it in

Add to the repo's existing lint command (package script, Makefile target, or whatever CI and the repo's CLAUDE.md or AGENTS.md tell agents to run), so the check runs wherever lint already runs:

```bash
ast-grep test --skip-snapshot-tests && ast-grep scan --no-ignore hidden --globs '!.git' && ! git grep -n --untracked 'ast-grep[-]ignore'
```

The scan flags are the ones from section 1: without them, comments in `.github/` and other hidden directories pass. The last part fails lint when `ast-grep-ignore` appears anywhere in the repo, comment or string, any line, any directory. Anything narrower is a way around it. Two details keep it honest:

- `--untracked`: plain `git grep` searches only tracked files, so a new file an agent hasn't staged yet would slip past. Files the repo's `.gitignore` excludes stay out, as they do for `ast-grep scan`.
- `[-]` matches the same text, but the command's own text doesn't contain `ast-grep-ignore`, so the Makefile or package.json holding it doesn't fail its own check.

Paste it into the lint target as is. It has no `$`, double quotes, or backslashes, so it needs no escaping in a Makefile recipe or a package.json script.

If CI doesn't run that lint command, add a step that does. If ast-grep is pinned in CI only, install it in a step before lint, after the setup step for its package manager (`actions/setup-node` for npm, `actions/setup-python` for pip); add that setup step if the workflow lacks it. If no agent instruction file in the repo tells agents to run lint before finishing, add one line saying so. Claude Code reads `CLAUDE.md`; Codex reads `AGENTS.md`. Add the line to whichever exists. Neither exists → create `CLAUDE.md` and make `AGENTS.md` a symlink to it, so both harnesses read the same line. Only one exists → add the line there, and say in the reply which harness won't see it. Don't add hooks.

## 5. Remove the existing comments

### Read them first

Before anything is deleted, read every comment in the section 1 dumps. A comment that holds a fact the code doesn't — a non-obvious unit, an external constraint, a known bug — is a finding. List it with a suggested home: a name, a type, a test, a doc, or an issue. Don't keep it as a comment.

Hundreds of comments → split the JSONL dumps into chunks and hand each to a subagent with this paragraph as its brief, asking for `path:line`, the comment, and the suggested home. Merge their lists.

### Remove them

```bash
ast-grep scan --no-ignore hidden --globs '!.git' -U
```

It exits 1 while matches without a fix remain, such as docstrings; that's expected here. The fix deletes the comment text only, so it leaves blank lines, trailing whitespace, and in JSX an empty `{}` behind. Run the repo's formatter if it has one; either way, then run:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/tidy.py"
```

It compares each changed file with `HEAD` and touches only the lines the removal changed: it strips trailing whitespace, drops lines left blank, drops a leftover JSX `{}`, caps a merged blank run at the longer of the two it joined, and removes blank lines left at the top of a file.

`-U` doesn't touch docstrings, because `no-docstrings-python` has no `fix`: removing one can leave a function or class with an empty body, which is a syntax error. Remove each by hand, adding `...` only where the body would otherwise be empty.

Unguarded comments the user chose to remove (Ask once): remove them by hand now.

## 6. Verify

All must hold. Report each with its evidence:

- Build, typecheck, lint, and test give the same results as the section 0 baseline. A difference means a removed comment was a directive. Find it, add it to the exceptions, restore it, and re-run.
- `ast-grep test --skip-snapshot-tests` passes.
- The full lint command from section 4 passes on the cleaned repo.
- The guard catches the file-level bypass: put a comment containing `ast-grep-ignore`, a blank line, and another comment in a new, unstaged file in the repo, run the repo's lint target (not the bare command), confirm it fails, and delete the file.

A check that can't run → say so and name what's missing. Don't call the setup done.

## 7. Reply

Don't commit. Leave everything in the working tree, and recommend two commits: the cleanup (section 5) first, then the guard (sections 3–4). In that order every commit passes lint; the guard alone would fail on the comments still there. Two things to tell the user with it:

- A file changed by both (a CI workflow that lost comments and gained the lint step) needs its hunks split: `git add -p`.
- The cleanup commit belongs in `.git-blame-ignore-revs` only if it survives merging. A squash merge folds both commits into one, and ignoring that hides the guard too. Squash-only repo → merge this one with a rebase or merge commit, or skip `.git-blame-ignore-revs`.

The facts from section 5 need a home before the change ships, or they're lost with the comments. Offer to file each as an issue, or write it into the repo's docs, in the same change.

```
## Annotation guard — <repo>
ast-grep <version>, pinned via <how>

## Rules
| Language | Comment kinds | Exceptions | Ignored paths |
| -------- | ------------- | ---------- | ------------- |

## Wired into
- `<file>` — <command or CI step>

## Cleanup
<n> comments removed across <m> files. Formatter: <command, or "none">; then tidy.py.

## Unguarded
- <file type or embedded code> — <count> files, <count> comments — <removed by hand | left>

## Verification
| Check | Before | After |
| ----- | ------ | ----- |

## Facts that need a home
- `path:line` — <removed comment> → <suggested name, type, test, or issue>
```
