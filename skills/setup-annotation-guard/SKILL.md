---
name: setup-annotation-guard
description: Ban code comments in a repo with an ast-grep rule, allowing only tool directives, wire it into the repo's lint and CI, and remove the comments already there.
disable-model-invocation: true
---

# Setup annotation guard

Install a lint rule in the target repo that fails on any code comment that isn't a tool directive. The code is the documentation: intent goes in names, types, structure, and tests; the reason for a change goes in its commit message. Comments that narrate past decisions are what later agents copy and trust, so none get written.

`$ARGUMENTS` is the target repo's path. Empty → the current working directory.

The guard is ast-grep, not this skill. Everything an agent is allowed to write lives in the rule files, where a change to it shows up in a diff and gets reviewed. This skill only sets the rule up.

## 0. Preconditions

- The target is a git repo with a clean working tree. Dirty → stop and ask; the cleanup in section 5 must be its own diff.
- ast-grep runs as `ast-grep`. Never as `sg`: on Linux that name is the setgroups command.
- Find the repo's own commands for build, typecheck, lint, and test (package scripts, Makefile, CI config). Run all four now and record each command, exit status, and pass/fail counts. This is the baseline section 6 compares against. A command that fails now is noted, not fixed.

## 1. Inventory

List the languages in the repo from `git ls-files`. For each, find which node kinds are comments. Verified against ast-grep 0.39.5:

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

Then dump every comment in the repo, one JSON object per line, and group them by their first few characters:

```bash
ast-grep scan --inline-rules '{id: c, language: <lang>, rule: {any: [{kind: <kind>}, …]}}' --json=stream . > <scratchpad>/comments-<lang>.jsonl
```

The groups that recur with a fixed prefix are the candidate directives. Everything else is prose.

Also find what must be skipped entirely: generated files (a `Code generated … DO NOT EDIT.` or `@generated` header), vendored code (`vendor/`, `third_party/`), and anything a generator rewrites. These keep their comments and go in the rule's `ignores`.

## 2. Exceptions

A comment is allowed only if a tool reads it, and only if that tool is configured in this repo. No ruff or flake8 config → no `noqa`. Start from these, and keep only what the inventory found or the repo's tools need:

| Tool | Allowed form |
| ---- | ------------ |
| shell, Python | `#!` shebang |
| Python | `# -*- coding: … -*-` |
| ruff, flake8 | `# noqa: <CODE>[, <CODE>]` (a bare `# noqa` stays banned) |
| mypy | `# type: ignore[<code>]` (bare stays banned) |
| pyright | `# pyright: ignore[<rule>]` |
| Go | `//go:build`, `//go:generate`, `//go:embed`, `//nolint:<linter>` |
| TypeScript | `// @ts-expect-error` (`@ts-ignore` stays banned: it never reports when it's no longer needed) |
| ESLint | `// eslint-disable-next-line <rule>`, `// eslint-disable-line <rule>` (file- and block-wide forms stay banned) |
| Prettier | `// prettier-ignore` |
| bundlers | `/*#__PURE__*/`, `/* @__PURE__ */`, `/* webpackChunkName: … */`, `/* @vite-ignore */` |
| coverage | `/* istanbul ignore … */`, `/* c8 ignore … */` |
| licensing | `SPDX-License-Identifier: …`, only if the repo already uses it |

Each exception is an anchored regex on the comment's full text (`^…$`). A suppression must name what it suppresses, so it can't quietly silence everything around it. Turn on the tool's own check for stale suppressions where it has one: ruff `RUF100`, ESLint `--report-unused-disable-directives`, mypy `warn_unused_ignores`.

`ast-grep-ignore` is never an exception. On the line before code it is itself a comment, so the rule flags it. But as the first line of a file, followed by a blank line, it silences every rule for the whole file, including itself, and the scan reports nothing. That's why section 4 adds a separate `git grep` for it.

### Ask once

Batch these into one question for the user, after the inventory and before writing rules:

- **Docstrings.** Python docstrings are strings, not comments, so `kind: comment` misses them. Ban them by default. Keep them only if the repo builds API docs from them (Sphinx, mkdocstrings, pdoc config present) and the user says so.
- **Directives the inventory found that aren't in the table above.** Show each, with a count and one example, and ask which a tool actually reads.
- **How to pin ast-grep** in this repo: a dev dependency (`@ast-grep/cli` in npm, `ast-grep-cli` in pip), or a pinned install in CI only. Pin an exact version; node kind names can change between releases.

## 3. Write the rules

At the repo root:

```
sgconfig.yml
rules/no-comments-<lang>.yml
rule-tests/no-comments-<lang>-test.yml
```

If the repo already has an `sgconfig.yml`, add to its `ruleDirs` and `testConfigs` instead.

```yaml
# sgconfig.yml
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

The rule files hold no comments of their own. They live in the repo, and an example comment there is the first thing the next agent copies.

When Python docstrings are banned, they get their own rule, `no-docstrings-python`, with the same `severity`, `message`, `note`, and `ignores`, and no `fix` (section 5 says why):

```yaml
rule:
  kind: expression_statement
  has: { kind: string }
```

A string standing alone as a statement does nothing at runtime, so this matches docstrings and nothing that runs.

`severity: error` makes `ast-grep scan` exit 1 on a match, so it can gate lint and CI. The `message` and `note` are what the next agent reads when it writes a comment, so they say what to do instead.

Every rule gets a test file. `valid` holds each allowed exception and a string containing comment characters (`"// x"`, `"# x"`). `invalid` holds a line comment, a trailing comment, a block comment, a doc comment, each banned variant of each exception (`# noqa`, `@ts-ignore`, `eslint-disable` without a rule), and `// ast-grep-ignore`. Write multi-line cases as `|` block scalars; `\n` inside single quotes stays a literal backslash and n.

```bash
ast-grep test --skip-snapshot-tests
```

## 4. Wire it in

Add to the repo's existing lint command (package script, Makefile target, or whatever CI and the repo's CLAUDE.md or AGENTS.md tell agents to run), so the check runs wherever lint already runs:

```bash
ast-grep test --skip-snapshot-tests && ast-grep scan && ! git grep -n 'ast-grep-ignore' -- ':!rules' ':!rule-tests'
```

If CI doesn't run that lint command, add a step that does. If no agent instruction file in the repo tells agents to run lint before finishing, add one line saying so. Don't add hooks.

## 5. Remove the existing comments

```bash
ast-grep scan -U
```

Then run the repo's formatter. The fix deletes the comment text only, so it leaves blank lines and trailing whitespace behind.

`-U` doesn't touch docstrings, because `no-docstrings-python` has no `fix`: removing one can leave a function or class with an empty body, which is a syntax error. Remove each by hand, adding `...` only where the body would otherwise be empty.

Look at what's being removed before it goes. A comment that holds a fact the code doesn't — a non-obvious unit, an external constraint, a known bug — is a finding. List it in the reply with a suggested home: a name, a type, a test, or an issue. Don't keep it as a comment.

## 6. Verify

All must hold. Report each with its evidence:

- Build, typecheck, lint, and test give the same results as the section 0 baseline. A difference means a removed comment was a directive. Find it, add it to the exceptions, restore it, and re-run.
- `ast-grep test --skip-snapshot-tests` passes.
- The full lint command from section 4 passes on the cleaned repo.
- The guard catches the file-level bypass: put `// ast-grep-ignore`, a blank line, and `// x` in a temp file in the repo, run the lint command, confirm it fails, and delete the file.

A check that can't run → say so and name what's missing. Don't call the setup done.

## 7. Reply

Don't commit. Leave everything in the working tree, and recommend two commits: the guard (sections 3–4), then the cleanup (section 5), so the cleanup can go in `.git-blame-ignore-revs`.

```
## Annotation guard — <repo>
ast-grep <version>, pinned via <how>

## Rules
| Language | Comment kinds | Exceptions | Ignored paths |
| -------- | ------------- | ---------- | ------------- |

## Wired into
- `<file>` — <command or CI step>

## Cleanup
<n> comments removed across <m> files. Formatter: <command>.

## Verification
| Check | Before | After |
| ----- | ------ | ----- |

## Facts that need a home
- `path:line` — <removed comment> → <suggested name, type, test, or issue>
```
