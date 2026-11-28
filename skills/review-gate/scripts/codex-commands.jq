# The commands a `codex exec --json` reviewer ran, one per line, for stop-gate.sh.
# Each is an item.started command_execution, wrapped as `<shell> -lc '<command>'`;
# unwrapped, or the install pattern never sees the command. With $all, every
# "command" field anywhere, for when that shape changes.
def unwrap:
  (if type == "array" then join(" ") else tostring end)
  | if test("^[^ ]*sh -l?c '") then
      capture("^[^ ]*sh -l?c '(?<c>.*)'$"; "m").c | gsub("'\\\\''"; "'")
    else . end;

if $all then (.. | objects | .command? // empty)
else select(.type == "item.started" and .item.type? == "command_execution") | .item.command
end
| unwrap
