# The commands a `codex exec --json` reviewer ran, one per line, for stop-gate.sh.
# Each is an item.started command_execution, wrapped as `<shell> -lc <word>`,
# where the word is single-quoted, double-quoted, or a mix of quoted runs
# ("rg -n '"'^'"\\s*x'"). Unquoted the way a shell would, or the install
# pattern never sees the command. With $all, every "command" field anywhere,
# for when that shape changes.

# One shell word, unquoted: '...' runs are literal; "..." runs take \\ \" \$ \`
# and a backslash-newline as escapes; outside quotes a backslash escapes the
# next character.
def shellword:
  [ scan("'[^']*'|\"(?:\\\\.|[^\"\\\\])*\"|\\\\.|[^'\"\\\\]+") ]
  | map(
      if startswith("'") then .[1:-1]
      elif startswith("\"") then .[1:-1] | gsub("\\\\(?<c>[\\\\\"$`\n])"; .c)
      elif startswith("\\") then .[1:]
      else . end)
  | join("");

def unwrap:
  (if type == "array" then join(" ") else tostring end)
  | if test("^[^ ]*sh -l?c ") then sub("^[^ ]*sh -l?c "; "") | shellword else . end;

if $all then (.. | objects | .command? // empty)
else select(.type == "item.started" and .item.type? == "command_execution") | .item.command
end
| unwrap
