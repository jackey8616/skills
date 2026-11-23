---
name: deepen
description: Turn a question into a deeper one — what a top professional would do, from what raw material, with which methods, checked by what — then rewrite the prompt to ask for exactly that.
disable-model-invocation: true
---

# Deepen

I want a deeper version of this task, not a bigger one. Before rewriting it: (1) say what a top professional in this field would do here that I'm not asking for; (2) name the rawest material they would start from instead of what has already been digested for me; (3) name the specific methods and tools they would use; (4) say what, other than you or me, would show the result is right. Then rewrite my prompt to ask for exactly that.

`$ARGUMENTS` is the prompt to deepen. Empty → use the user's most recent request in this conversation, and quote it back first so they can see which one you took. No earlier request either → ask. Do nothing else first.

Reply in the user's language.

## Deeper, not bigger

Keep the question's scope. Deeper means a better starting point, sharper methods, and a real check — not more subtopics, more options, or a longer report. If the rewrite asks about anything the original didn't, cut it.

## 1. Name the professional

Pick the one role who would own this question for a living, as precisely as the question allows: "a forensic accountant auditing revenue recognition", not "a finance expert". If the question spans fields, pick the one whose judgement decides the answer, and say why in one line.

Every answer below is what that person would do — on this question, not in general.

## 2. Answer the four

Be specific enough that someone could act on each line tomorrow. Generic advice ("consult primary sources", "use best practices", "test thoroughly") fails this step — name which source, which practice, which test.

1. **What they'd do that I'm not asking for.** The move the professional makes by reflex that the prompt skips: questioning the framing, pinning a definition, checking a base rate, looking for the failure case first. One to three moves, each with why it matters here.
2. **The rawest material.** What they'd start from instead of summaries, blog posts, or your recollection: the dataset, the filing, the source code, the logs, the spec, the original paper, the measurement itself. Name it concretely — where it lives, what it's called. Say which of it you can reach in this session and which the user would have to supply.
3. **Methods and tools.** The named techniques, instruments, libraries, or procedures they'd use on that material, and what each one is for in this question.
4. **What shows it's right, other than you or me.** An outside check that doesn't rest on trusting either of us: a test that can fail, a reproduction, a measurement, a prediction checked against later data, a published standard, a second independent source, a domain expert's review. Say what result would show the answer is wrong.

## 3. Rewrite the prompt

Write the new prompt the user would send. It asks for exactly what sections 1–2 found, in the user's voice, as one self-contained block they can copy:

- Names the raw material to start from, and asks for it where the model can't reach it.
- Names the methods to apply.
- States the check and the result that would count as failure.
- Asks for the answer to say what it's unsure of and what it couldn't check.
- Stays the same size as the question. No new topics.

## 4. Stop

Don't run the rewritten prompt. Ask whether to run it, adjust it, or supply the missing material first.

## Reply

```
## Who'd own this
<role> — <one line on why>

## What they'd do that you're not asking for
- <move> — <why it matters here>

## Rawest material
- <material> — <where it is> — <reachable here | you'd need to supply it>

## Methods and tools
- <method or tool> — <what it's for here>

## What shows it's right
- <outside check> — <result that would show it's wrong>

## Rewritten prompt
<the prompt, ready to copy>
```
