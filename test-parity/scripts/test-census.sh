#!/usr/bin/env bash
# Census the test cases in a source tree, one row per test.
#
# Output: <file>\t<identifier>\t<line>
#
# Counts test *cases*, not test files or assertions, because a case is what an
# upstream author decided was one thing worth pinning. Matching is by the
# registration syntax of each framework a GNOME app might use, so it is a lead
# and not a verdict: read the files.
#
# Usage: test-census.sh <tree> [more-trees...]
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: $(basename "$0") <tree>..." >&2; exit 2; }

testfiles() {
  find "$1" -type f \
    -not -path '*/.git/*' -not -path '*/_build/*' -not -path '*/build/*' \
    -not -path '*/node_modules/*' -not -path '*/vendor/*' \
    -not -path '*/subprojects/*' -not -path '*/.bundle/*' -not -path '*/.claude/skills/*' \
    \( -path '*test*' -o -path '*spec*' -o -path '*Test*' \) \
    \( -name '*.vala' -o -name '*.c' -o -name '*.py' -o -name '*.js' \
       -o -name '*.ts' -o -name '*.rs' -o -name '*.rb' -o -name '*.cpp' \) 2>/dev/null
}

emit() {  # emit <file> <grep-ere> <sed-to-identifier>
  grep -nEo "$2" "$1" 2>/dev/null | while IFS=: read -r line match; do
    id=$(printf '%s' "$match" | sed -E "$3")
    [ -n "$id" ] && printf '%s\t%s\t%s\n' "$1" "$id" "$line"
  done
}

for tree in "$@"; do
  testfiles "$tree" | while IFS= read -r f; do
    case "$f" in
      # GLib test framework: Test.add_func ("/suite/case", ...) / g_test_add_func
      *.vala|*.c|*.cpp)
        emit "$f" '(g_)?[Tt]est(\.|_)add_func *\( *"[^"]+"' 's/.*"([^"]+)".*/\1/' ;;
      # unittest methods and pytest functions
      *.py)
        emit "$f" '^[[:space:]]*(async +)?def +test[A-Za-z0-9_]*' 's/.*def +//' ;;
      # Jasmine/Mocha it(...) — GJS apps and any JS/TS port
      *.js|*.ts)
        emit "$f" "\\b(it|test)\\( *['\"][^'\"]+['\"]" "s/.*['\"]([^'\"]+)['\"].*/\\1/" ;;
      # Rust: the attribute is the registration; the fn name is the identifier
      *.rs)
        grep -nA3 '#\[\(tokio::\)\?test\]' "$f" 2>/dev/null \
          | grep -oE '[0-9]+-[[:space:]]*(async )?fn [A-Za-z0-9_]+' \
          | sed -E 's/^([0-9]+)-.*fn +([A-Za-z0-9_]+)/\2\t\1/' \
          | while IFS=$'\t' read -r id line; do printf '%s\t%s\t%s\n' "$f" "$id" "$line"; done ;;
      # Ruby: minitest def test_*, spec-style it "...", and the house style
      # used across this fleet's ports - a named check(...) block, or
      # d.check(...) under the ruby-gtk-testing driver. A `check` is the named
      # assertion unit, which is what a GLib Test.add_func case is too; a
      # driver `step` is a grouping and is deliberately not counted.
      *.rb)
        emit "$f" '^[[:space:]]*def +test_[A-Za-z0-9_?!]*' 's/.*def +//'
        emit "$f" "^[[:space:]]*it +['\"][^'\"]+['\"]" "s/.*['\"]([^'\"]+)['\"].*/\\1/"
        emit "$f" "(^|[^A-Za-z_.])(d\\.)?check\\( *['\"][^'\"]+['\"]" "s/.*['\"]([^'\"]+)['\"].*/\\1/" ;;
    esac
  done
done | sort -u
