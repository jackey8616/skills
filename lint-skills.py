#!/usr/bin/env python3
"""Check every skill against the rules in CLAUDE.md.

    python3 lint-skills.py [repo-root]

Frontmatter and agents/openai.yaml are read with PyYAML, so quotes,
comments, and continuation lines mean what PyYAML (YAML 1.1) reads them as.
Where parsers disagree, the lint asks for the form they all read alike: no
key written twice at any depth, and the two booleans the rules depend on
spelled `true` and `false`, not `yes`, `on`, and the like.

Per skill:
  - SKILL.md opens with frontmatter that is a YAML mapping
  - name: matches the directory; lowercase words joined by hyphens, <= 64
  - description: a non-empty string, on the description: line itself,
    <= 1024 characters
  - disable-model-invocation: true, spelled so, or absent
  - user-invoked descriptions don't say "use when" (at a word start, any
    case); model-invoked ones do
  - agents/openai.yaml: interface.display_name and interface.short_description
    are non-empty strings; policy.allow_implicit_invocation is the boolean
    false, spelled so, for a user-invoked skill, and a model-invoked one has
    no policy
  - a row in README.md's skill table: a line starting | [`name`](skills/name/SKILL.md) |
  - every ${CLAUDE_SKILL_DIR}/... path in SKILL.md exists
  - a non-empty scripts/ comes with tests/*.test.sh
  - SKILL.md past 500 lines: a warning only
Repo-wide:
  - README.md links no path under skills/ that doesn't exist, inline or
    reference-style, with or without a leading ./
  - every *.test.sh sits at the repo root or in skills/<name>/tests/, not
    hidden, where CI's glob finds it, and is listed in CLAUDE.md

Prints one FAIL line per broken rule and exits 1 if there is any. WARN lines
don't change the exit status. Exits 2 if PyYAML isn't installed.
"""

import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("PyYAML not found. Install it: pip install pyyaml", file=sys.stderr)
    sys.exit(2)

MAX_LINES = 500
MAX_DESCRIPTION = 1024
NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
USE_WHEN = re.compile(r"\buse when", re.IGNORECASE)
SKILL_DIR_REF = re.compile(r"\$\{CLAUDE_SKILL_DIR\}/([^\s\"'`)]*)")
README_LINK = re.compile(r"\]\(\s*<?(?:\./)?(skills/[^)\s#?>]*)")
README_REF = re.compile(r"^ {0,3}\[[^\]]+\]:\s*<?(?:\./)?(skills/[^\s#?>]*)", re.MULTILINE)

failures = []


def fail(message):
    failures.append(message)
    print(f"FAIL {message}")


def warn(message):
    print(f"WARN {message}")


def frontmatter(text):
    """The text between an opening `---` on line 1 and the next `---` line."""
    lines = text.split("\n")
    if not lines or lines[0].rstrip("\r") != "---":
        return None
    for i, line in enumerate(lines[1:], start=1):
        if line.rstrip("\r") == "---":
            return "\n".join(lines[1:i]) + "\n"
    return None


def load(text, where):
    """Parse YAML text into (data, root node), or report why it can't be."""
    try:
        node = yaml.compose(text, Loader=yaml.SafeLoader)
        data = yaml.safe_load(text)
    except yaml.YAMLError as e:
        problem = getattr(e, "problem", None) or str(e).splitlines()[0]
        mark = getattr(e, "problem_mark", None)
        at = f" (line {mark.line + 1})" if mark else ""
        fail(f"{where}: not valid YAML: {problem}{at}")
        return None, None
    if not isinstance(data, dict):
        fail(f"{where}: must be a YAML mapping")
        return None, None
    duplicates = duplicate_keys(node)
    if duplicates:
        for key in duplicates:
            fail(f"{where}: {key}: appears twice")
        return None, None
    return data, node


def duplicate_keys(node, prefix="", seen=None):
    """Dotted paths of every key written twice in one mapping, at any depth."""
    seen = set() if seen is None else seen
    if id(node) in seen:
        return []
    seen.add(id(node))
    found = []
    if isinstance(node, yaml.MappingNode):
        keys = [k.value for k, _ in node.value if isinstance(k, yaml.ScalarNode)]
        found += [prefix + k for k in sorted({k for k in keys if keys.count(k) > 1})]
        for k, v in node.value:
            name = k.value if isinstance(k, yaml.ScalarNode) else "?"
            found += duplicate_keys(v, f"{prefix}{name}.", seen)
    elif isinstance(node, yaml.SequenceNode):
        for i, item in enumerate(node.value):
            found += duplicate_keys(item, f"{prefix}{i}.", seen)
    return found


def pair(root, key):
    """The (key node, value node) written for `key`, or None if it isn't
    written out at the top level (a merge key, say)."""
    for k, v in root.value:
        if k.value == key:
            return k, v
    return None


def written_text(root, *keys):
    """The source text of the scalar at `keys`, written out key by key from
    `root`; None if any step is missing or comes from a merge key."""
    node = root
    for key in keys:
        found = pair(node, key) if isinstance(node, yaml.MappingNode) else None
        if found is None:
            return None
        node = found[1]
    return node.value if isinstance(node, yaml.ScalarNode) else None


def non_empty_string(value):
    return isinstance(value, str) and value.strip() != ""


def check_skill(readme, skill_dir):
    name = skill_dir.name
    at = f"skills/{name}"
    skill = skill_dir / "SKILL.md"
    if not skill.is_file():
        fail(f"{at}: no SKILL.md")
        return
    text = skill.read_text(encoding="utf-8")

    block = frontmatter(text)
    if block is None:
        fail(f"{at}/SKILL.md: no frontmatter (line 1 must be ---, closed by another ---)")
        return
    fm, fm_root = load(block, f"{at}/SKILL.md frontmatter")
    if fm is None:
        return

    if fm.get("name") != name:
        fail(f"{at}/SKILL.md: name is {fm.get('name')!r}, the directory is {name!r}")
    if not NAME.match(name) or len(name) > 64:
        fail(f"{at}: name must be lowercase words joined by hyphens, at most 64 characters")

    description = fm.get("description")
    if not non_empty_string(description):
        fail(f"{at}/SKILL.md: no description")
        description = ""
    else:
        written = pair(fm_root, "description")
        key, node = written if written else (None, None)
        if node is None or node.style in ("|", ">") or not (
            key.start_mark.line == node.start_mark.line == node.end_mark.line
        ):
            fail(f"{at}/SKILL.md: description must be on the description: line itself")
        if len(description) > MAX_DESCRIPTION:
            fail(f"{at}/SKILL.md: description is {len(description)} characters, the limit is {MAX_DESCRIPTION}")

    dmi = fm.get("disable-model-invocation")
    user_invoked = dmi is True
    if "disable-model-invocation" in fm and dmi is not True:
        fail(f"{at}/SKILL.md: disable-model-invocation is {yaml.safe_dump(dmi).splitlines()[0]}; set it to true or omit it")
    elif dmi is True and written_text(fm_root, "disable-model-invocation") != "true":
        raw = written_text(fm_root, "disable-model-invocation")
        fail(f"{at}/SKILL.md: disable-model-invocation is {raw or 'merged in'}; write it as true, on its own key")

    if user_invoked and USE_WHEN.search(description):
        fail(f'{at}/SKILL.md: user-invoked, so the description has no "Use when" trigger; one human-facing line')
    elif not user_invoked and description and not USE_WHEN.search(description):
        fail(f'{at}/SKILL.md: model-invoked, so the description needs "Use when" trigger phrasing ("Use when the user…")')

    yaml_path = skill_dir / "agents" / "openai.yaml"
    if not yaml_path.is_file():
        fail(f"{at}: no agents/openai.yaml")
    else:
        agent, agent_root = load(yaml_path.read_text(encoding="utf-8"), f"{at}/agents/openai.yaml")
        if agent is not None:
            interface = agent.get("interface")
            if not isinstance(interface, dict):
                fail(f"{at}/agents/openai.yaml: no interface: block")
            else:
                for key in ("display_name", "short_description"):
                    if not non_empty_string(interface.get(key)):
                        fail(f"{at}/agents/openai.yaml: no interface.{key}")
            policy = agent.get("policy")
            if user_invoked:
                if not (isinstance(policy, dict) and policy.get("allow_implicit_invocation") is False):
                    fail(f"{at}: user-invoked in SKILL.md, but agents/openai.yaml lacks policy.allow_implicit_invocation: false")
                else:
                    raw = written_text(agent_root, "policy", "allow_implicit_invocation")
                    if raw != "false":
                        fail(f"{at}/agents/openai.yaml: policy.allow_implicit_invocation is {raw or 'merged in'}; write it as false, on its own key")
            elif "policy" in agent:
                fail(f"{at}: model-invoked in SKILL.md, so agents/openai.yaml has no policy block")

    row = f"| [`{name}`](skills/{name}/SKILL.md) |"
    if not any(line.startswith(row) for line in readme.splitlines()):
        fail(f"{at}: no row in README.md's skill table")

    for ref in sorted({m.rstrip(".,;:?!") for m in SKILL_DIR_REF.findall(text)}):
        if not (skill_dir / ref).exists():
            fail(f"{at}/SKILL.md: points at ${{CLAUDE_SKILL_DIR}}/{ref}, which doesn't exist")

    scripts = skill_dir / "scripts"
    if scripts.is_dir() and any(scripts.iterdir()) and not list((skill_dir / "tests").glob("*.test.sh")):
        fail(f"{at}: has scripts/ but no tests/*.test.sh")

    lines = text.count("\n")
    if lines > MAX_LINES:
        warn(f"{at}/SKILL.md: {lines} lines; past {MAX_LINES}, move detail into references/ and point at it")


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent)
    skills = root / "skills"
    if not skills.is_dir():
        print(f"FAIL no skills/ directory in {root}")
        return 1

    readme_path = root / "README.md"
    readme = readme_path.read_text(encoding="utf-8") if readme_path.is_file() else ""
    claude_path = root / "CLAUDE.md"
    claude = claude_path.read_text(encoding="utf-8") if claude_path.is_file() else ""

    for skill_dir in sorted(p for p in skills.iterdir() if p.is_dir()):
        check_skill(readme, skill_dir)

    for link in sorted(set(README_LINK.findall(readme) + README_REF.findall(readme))):
        if not (root / link).exists():
            fail(f"README.md: links {link}, which doesn't exist")

    tests = sorted(
        t for t in root.rglob("*.test.sh")
        if not any(part.startswith(".") for part in t.relative_to(root).parts[:-1])
    )
    for test in tests:
        rel = test.relative_to(root).as_posix()
        parts = test.relative_to(root).parts
        placed = len(parts) == 1 or (len(parts) == 4 and parts[0] == "skills" and parts[2] == "tests")
        if not placed or parts[-1].startswith("."):
            fail(f"{rel}: tests sit at the repo root or in skills/<name>/tests/, where CI runs them")
        if f"bash {rel}`" not in claude:
            fail(f"{rel}: not listed under the tests in CLAUDE.md")

    if failures:
        print(f"{len(failures)} failed")
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
