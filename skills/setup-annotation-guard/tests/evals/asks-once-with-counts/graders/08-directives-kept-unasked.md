---
type: llm
focus: trace
weight: 1
---

The run treats the shebang in scripts/export.py and # noqa: E501 in
notes/store.py as directives to keep, the noqa because ruff is configured in
pyproject.toml, without asking about either.
