#!/bin/sh
# Compile-checks every GDScript file headlessly.
GODOT=${GODOT:-godot}
for f in $(find scripts tools -name '*.gd'); do
  out=$($GODOT --headless --path . --check-only -s "$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error" | grep -vE "not found: (Settings|Save)|depended scripts" | head -5)
  [ -n "$out" ] && echo "== $f" && echo "$out"
done
echo "check done"
