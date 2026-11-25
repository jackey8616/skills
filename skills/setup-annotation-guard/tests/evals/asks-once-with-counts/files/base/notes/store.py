"""Keep notes in a JSON file."""
import json
from pathlib import Path

# Notes live in one file so a backup is a single copy.
DEFAULT_PATH = Path("notes.json")


def load(path=DEFAULT_PATH):
    """Return the notes saved at path, or an empty list."""
    if not path.exists():
        return []
    return json.loads(path.read_text())


def save(notes, path=DEFAULT_PATH):
    path.write_text(json.dumps(notes, indent=2))  # indent keeps diffs readable


def title_of(note):
    return note.get("title") or note.get("body", "").split("\n", 1)[0][:60].strip()  # noqa: E501
