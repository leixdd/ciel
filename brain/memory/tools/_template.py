"""TOOL TEMPLATE — copy to <name>.py in this folder; discovery is automatic.
(_-prefixed files like this one are skipped.)

Contract:
  NAME        str, unique, what the model calls
  DESCRIPTION str, one sentence the model reads to decide when to call it
  PARAMETERS  dict, JSON schema for the arguments
  PERMISSION  str|None, optional TCC key the app can check (e.g. "calendars")
  run(**args) -> str  compact plain text; the LLM summarizes it aloud, so no
                      markdown, cap the length. NEVER raise for expected
                      failures (missing permission, nothing found) — return a
                      helpful sentence instead. Import heavy deps lazily
                      inside run() so engine startup pays nothing.
"""
NAME = "example"
DESCRIPTION = "Explain here exactly when the model should call this tool."
PARAMETERS = {
    "type": "object",
    "properties": {"query": {"type": "string", "description": "What to look up."}},
    "required": [],
}
PERMISSION = None  # or a TCC key the app can check, e.g. "calendars"

def run(query=""):
    return f"compact plain-text result for {query!r}"
