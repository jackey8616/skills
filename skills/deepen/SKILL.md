---
name: deepen
description: Turn a question into a deeper one by asking several fields how they'd attack it — what each does that you skipped, from what raw material, with which methods, checked by what — then rewrite the prompt to ask for the strongest mix.
disable-model-invocation: true
---

# Deepen

I want a deeper version of this task, not a bigger one. Before rewriting it, get a second opinion from several fields that would attack it differently. For each: (1) say what that field would do here that I'm not asking for; (2) name the rawest material it would start from instead of what has already been digested for me; (3) name the specific methods and tools it would use; (4) say what, other than you or me, would show the result is right. Then rewrite my prompt to ask for the strongest mix of that.

`$ARGUMENTS` is the prompt to deepen. Empty → use the user's most recent request in this conversation, and quote it back first so they can see which one you took. No earlier request either → ask. Do nothing else first.

Reply in the user's language.

## Wider methods, same question

The fields widen how the question is attacked, never what it asks. Deeper means a better starting point, sharper methods, and a real check — not more subtopics, more options, or a longer report. If the rewrite asks about anything the original didn't, cut it.

## 1. Pick the fields

Pick as many fields as the question needs — each one working it with different methods. Typically:

- **The home field** — the one the question obviously belongs to.
- **Neighbours** — fields that study the same thing from another angle, with their own data and tools.
- **One outsider** — a field that doesn't own this topic but has a method that fits its shape: forecasting for a decision under uncertainty, epidemiology for a "does X cause Y", reliability engineering for "why does this keep failing", historiography for "what really happened".

Each field earns its place with a method the others don't bring. Two fields that would do the same thing → keep one. Stop adding when the next field brings nothing new. Name fields as disciplines, not people or personas.

## 2. Answer the four, per field

Answer from how each field actually does the work — its standard practice — not by playing a character. Be specific enough that someone could act on each line tomorrow. Generic advice ("consult primary sources", "use best practices", "test thoroughly") fails this step — name which source, which practice, which test.

1. **What it does that I'm not asking for.** The move the field makes by reflex that the prompt skips: questioning the framing, pinning a definition, checking a base rate, looking for the failure case first. One or two moves, each with why it matters here.
2. **The rawest material.** What it starts from instead of summaries, blog posts, or your recollection: the dataset, the filing, the source code, the logs, the spec, the original paper, the measurement itself. Name it concretely — where it lives, what it's called. Say which of it you can reach in this session and which the user would have to supply.
3. **Methods and tools.** The named techniques, instruments, libraries, or procedures it uses on that material, and what each one is for in this question.
4. **What shows it's right, other than you or me.** An outside check that doesn't rest on trusting either of us: a test that can fail, a reproduction, a measurement, a prediction checked against later data, a published standard, a second independent source. Say what result would show the answer is wrong.

## 3. Compare

Line the fields up against each other before choosing:

- **Where they disagree** — on the framing, on what counts as evidence, on what the answer even is. A disagreement is a finding; don't smooth it over.
- **Blind spots** — what one field would catch that the home field would miss.
- **The strongest check** — the one most likely to expose a wrong answer. Checks from different fields that agree are stronger than any one alone.

## 4. Rewrite the prompt

Write the new prompt the user would send, in the user's voice, as one self-contained block they can copy. It takes the best of each field, not all of it:

- Names the raw material to start from, and asks for it where the model can't reach it.
- Names the methods to apply, and which field each comes from only when that helps.
- Asks the answer to address the disagreements from section 3, not pick a side silently.
- Doesn't assign a role or persona ("act as a…"). It asks for the work directly.
- States the checks and the result that would count as failure.
- Asks for the answer to say what it's unsure of and what it couldn't check.
- Stays the same question. No new topics.

## 5. Stop

Don't run the rewritten prompt. Ask whether to run it, adjust it, swap a field, or supply the missing material first.

## Reply

```
## Fields
- <field> — <the method it brings that the others don't>

## <field>
- Skipped move: <move> — <why it matters here>
- Raw material: <material> — <where it is> — <reachable here | you'd need to supply it>
- Methods: <method or tool> — <what it's for here>
- Check: <outside check> — <result that would show it's wrong>

(repeat per field)

## Where they part ways
- Disagreements: <what, between which fields>
- Blind spots: <what the home field would miss, caught by which field>
- Strongest check: <check> — <why>

## Rewritten prompt
<the prompt, ready to copy>
```
