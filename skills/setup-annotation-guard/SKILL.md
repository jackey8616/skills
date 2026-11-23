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
- The inventory needs ast-grep before the user picks how to pin it. Use the one on PATH. None → install one into your scratchpad, outside the repo (`npm install --prefix <scratchpad>/ast-grep @ast-grep/cli@<version>`), and say so in the reply. Prefer 0.39.5, the version this skill's tables were checked against.
- Find the repo's own commands for build, typecheck, lint, and test (package scripts, Makefile, CI config). Run all four now and record each command, exit status, and pass/fail counts. This is the baseline section 6 compares against. A command that fails now is noted, not fixed. A command the repo doesn't have is recorded as absent.

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
- Code inside a string is invisible: a YAML `run: |` block is a YAML string, so the shell comments in it are never seen. The same goes for SQL in string literals. Find them by hand (`git grep -n` for `run: |` and the like), and extract every comment in them now into `<scratchpad>/comments-embedded.jsonl`: one object per comment with its file, line, and full text. Do it before section 4 edits any of those files, so the record doesn't depend on line numbers that will shift. Section 5 reads this file with the others, and removes each comment by its text.

Unparseable files and invisible embedded code both go in the reply under Unguarded. Whether their existing comments go is the user's call (Ask once). Run section 2's directive check over them too: unguarded files hold tool directives like any other (`--> statement-breakpoint` in a Drizzle migration, `-- +goose Up`, `# syntax=docker/dockerfile:1`), and removing one breaks the tool. Migrations are better left alone entirely.

Markdown is prose, not code: leave it out of the inventory and the counts. Its `#` lines are headings, not comments.

Then dump every comment in the repo, one JSON object per line, and group them by their first few characters:

```bash
ast-grep scan --no-ignore hidden --globs '!.git' --inline-rules '{id: c, language: <lang>, rule: {any: [{kind: <kind>}, …]}}' --json=stream . > <scratchpad>/comments-<lang>.jsonl
```

By default ast-grep skips hidden directories, so `.github/workflows` and the like would never be seen. `--no-ignore hidden` brings them in, and `--globs '!.git'` keeps git's own directory out. `.gitignore` is still honoured. Every `ast-grep scan` in this skill takes the same two flags.

The groups that recur with a fixed prefix are the candidate directives. Everything else is prose.

Also find what must be skipped entirely: generated files (a `Code generated … DO NOT EDIT.` or `@generated` header), vendored code (`vendor/`, `third_party/`), anything a generator rewrites, and test inputs captured from outside: fixtures, snapshots (`__snapshots__/`, `*.snap`), saved HTML pages, recorded API responses (cassettes, `*.har`), golden files. Changing a captured input changes what the test checks; an HTML fixture's `<script>` is reached by the JavaScript rule and `-U` would rewrite it. All of these keep their comments and go in `ignores`.

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

Batch these four into one question for the user (one AskUserQuestion call; it takes four at most), after the inventory and before writing rules. The only other question comes in section 7, about the facts.

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

`ignores` applies only to the rule it's written in. A file reached by several rules needs the path in each: an `.html` fixture is scanned by the HTML, JavaScript, and CSS rules, so all three list it.

A language with no exceptions drops the `not:` block. The rule files hold no comments of their own. They live in the repo, and an example comment there is the first thing the next agent copies.

Position-bound exceptions go in the same `not: any:` list. The Python forms; for Bash use `kind: program` in place of `module`:

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

The alternations are examples; use the exact shebangs and encodings the inventory found. `stopBy: neighbor` is `inside`'s default, written out because it's what makes this work: the comment's direct parent must be the file itself. With `stopBy: end`, a comment at any depth would pass. The first allows a listed shebang only when no other node precedes it. The second allows a listed coding line only at the top level, with nothing but a shebang before it.

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

Every rule gets a test file. `valid` holds each allowed exception and a string containing comment characters (`"// x"`, `"# x"`). `invalid` holds a line comment, a trailing comment, a block comment, a doc comment, and each banned variant of each exception (`# noqa`, `@ts-ignore`, `eslint-disable` without a rule). Leave `ast-grep-ignore` out of the fixtures too: section 4 bans it everywhere, test files included. Write any case that spans lines or contains `: `, `{`, or `#` as a `|` block scalar. Unquoted, `: ` makes YAML read the case as a map and `#` starts a YAML comment, and the whole test file fails to parse; inside single quotes, `\n` stays a literal backslash and n. HTML is the exception to the comment-characters case: its grammar parses `<!--` inside an attribute value as a comment, so leave that case out of an HTML rule's `valid`.

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

No lint command in the repo → create one where the repo keeps its commands (a `lint` script in `package.json`, a `lint` target in the Makefile), holding just this. If CI doesn't run that lint command, add a step that does. Then update the docs that list the repo's development commands (README, CONTRIBUTING): a list of "the checks CI runs" is now one short. If ast-grep is pinned in CI only, install it in a step before lint, after the setup step for its package manager (`actions/setup-node` for npm, `actions/setup-python` for pip); add that setup step if the workflow lacks it. If no agent instruction file in the repo tells agents to run lint before finishing, add one line saying so. Claude Code reads `CLAUDE.md`; Codex reads `AGENTS.md`. Add the line to whichever exists. Neither exists → create both, each with the same line. Not a symlink: a Windows clone without `core.symlinks` checks a symlink out as a text file holding the target's name, and Codex reads that instead. Only one exists → add the line there, and say in the reply which harness won't see it. Don't add hooks.

## 5. Remove the existing comments

### Read them first

Before anything is deleted, read every comment in the section 1 dumps. A comment that holds a fact the code doesn't — a non-obvious unit, an external constraint, a known bug — is a finding. List it with a suggested home: a name, a type, a test, a doc, or an issue. Don't keep it as a comment.

Comments go stale; that's why they're being removed. So check each fact against the code as it is now before it goes anywhere. Still true → keep it. No longer true → drop it, and list it in the reply as stale.

Sort each fact by where it belongs:

- **Prose**: why the code is this way, an external constraint, domain context. → Docs. Only what a reader can't get from the code and what will stay true; the rest is noise in the docs.
- **Code**: a name, a constant, a type, or a test would say it. → An issue, or a follow-up change. Not part of this cleanup.
- **Already said**: a test or a name says it now. → Drop it.

Hundreds of comments → split the JSONL dumps into chunks and hand each to a subagent. Its brief is this subsection, plus section 2's rule with this repo's answer: a comment is a directive only if its tool is configured here, and the configured tools are <list>. Without that, a subagent will call an `eslint-disable` essential in a repo that doesn't run ESLint. Ask each for `path:line`, the comment, its category, and its home. Merge their lists.

Thousands of comments → before the subagents, make one quick pass that drops comments that only restate the line below them (`// increment i`), and hand the rest on.

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

Unguarded comments the user chose to remove (Ask once): remove them by hand now. For embedded ones, find each by its text from `comments-embedded.jsonl`, not by its recorded line.

## 6. Verify

All must hold. Report each with its evidence:

- Build, typecheck, lint, and test give the same results as the section 0 baseline. A difference means a removed comment was a directive. Find it, add it to the exceptions, restore it, and re-run. A lint command this skill created has no baseline; report it as absent before, passing after.
- `ast-grep test --skip-snapshot-tests` passes.
- The full lint command from section 4 passes on the cleaned repo.
- The guard catches the file-level bypass: put a comment containing `ast-grep-ignore`, a blank line, and another comment in a new, unstaged file in the repo, run the repo's lint target (not the bare command), confirm it fails, and delete the file.

A check that can't run → say so and name what's missing. Don't call the setup done.

## 7. Reply

Don't commit. Leave everything in the working tree, and recommend two commits: the cleanup (section 5) first, then the guard (sections 3–4). In that order every commit passes lint; the guard alone would fail on the comments still there. Two things to tell the user with it:

- A file changed by both (a CI workflow that lost comments and gained the lint step) needs its hunks split. Interactively, `git add -p`. Without a terminal: take the guard's lines out of the file, stage it with the cleanup and commit, put the lines back, then stage and commit the guard.
- The cleanup commit belongs in `.git-blame-ignore-revs` only if it survives merging. A squash merge folds both commits into one, and ignoring that hides the guard too. Squash-only repo → merge this one with a rebase or merge commit, or skip `.git-blame-ignore-revs`.

The facts from section 5 need a home before the change ships, or they're lost with the comments. Ask the user, as its own question, per category: prose facts into the docs in this change, or listed only; code facts filed as issues, or listed only. Already-said facts are dropped without asking.

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
| Category | `path:line` | Removed comment | Home |
| -------- | ----------- | --------------- | ---- |
| prose / code | | | <doc, or name, constant, type, test, issue> |

<n> already said by a test or name, dropped.

## Stale facts dropped
- `path:line` — <removed comment> — <what the code does now>
```
