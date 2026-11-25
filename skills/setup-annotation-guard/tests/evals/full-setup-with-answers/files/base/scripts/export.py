#!/usr/bin/env python3
from notes.store import load

# Print every note title, one per line.
for note in load():
    print(note.get("title", ""))
