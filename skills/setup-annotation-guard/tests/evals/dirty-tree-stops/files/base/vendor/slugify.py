# Vendored from slugify-lite 1.2, MIT licence.
import re


def slugify(text):
    # Lowercase, and replace each run of other characters with one hyphen.
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
