#!/usr/bin/env bash
# Inventory the UI components of a GTK app, per file.
#
# Output: <file>\t<kind>\t<value>\t<count>
#   kind = widget  a Gtk/Adw type instantiated or declared in that file
#          css     a CSS class attached to a widget in that file
#          signal  a signal that file connects a handler to
#          action  a GAction name installed or referenced in that file
#
# Per file, not per instance: grep cannot reconstruct a widget tree, and in
# both Vala upstreams and the Ruby house style one file is one component class,
# which makes the file the unit the two sides can actually be joined on.
# The counts are what carry instance multiplicity - three AdwActionRows in a
# file is `widget Adw.ActionRow 3`.
#
# Paths are printed relative to the tree, so two trees can be diffed directly.
#
# Usage: component-scan.sh <tree>
set -uo pipefail

[ $# -eq 1 ] || { echo "usage: $(basename "$0") <tree>" >&2; exit 2; }
TREE=${1%/}

srcfiles() {
  find "$TREE" -type f \
    -not -path '*/.git/*' -not -path '*/po/*' -not -path '*/_build/*' \
    -not -path '*/build/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' \
    -not -path '*/subprojects/*' -not -path '*/.bundle/*' \
    -not -path '*/.claude/skills/*' \
    \( -name '*.ui' -o -name '*.blp' -o -name '*.vala' -o -name '*.c' \
       -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.rs' \
       -o -name '*.rb' \) 2>/dev/null
}

# tally <file> <kind> — reads matched values on stdin, emits deduped rows with counts
tally() {
  sed 's/^ *//; s/ *$//' | grep -v '^$' | sort | uniq -c \
    | awk -v f="$1" -v k="$2" '{c=$1; $1=""; sub(/^ /,""); print f "\t" k "\t" $0 "\t" c}'
}

srcfiles | while IFS= read -r f; do
  rel=${f#"$TREE"/}

  # --- widgets -------------------------------------------------------------
  # Normalised to Ns.Type so Vala `new Adw.ActionRow`, GtkBuilder
  # class="AdwActionRow" and Ruby `Adwaita::ActionRow.new` all land on the same
  # value. Ruby spells libadwaita `Adwaita::`; it is folded back to `Adw`.
  {
    grep -ohE 'class="(Adw|Gtk)[A-Za-z0-9]+"' "$f" 2>/dev/null \
      | sed -E 's/class="(Adw|Gtk)([A-Za-z0-9]+)"/\1.\2/'
    grep -ohE '\b(Adw|Gtk|Adwaita)\.[A-Z][A-Za-z0-9]+' "$f" 2>/dev/null \
      | sed -E 's/^Adwaita\./Adw./'
    grep -ohE '\b(Adw|Gtk|Adwaita)::[A-Z][A-Za-z0-9]+' "$f" 2>/dev/null \
      | sed -E 's/::/./; s/^Adwaita\./Adw./'
    # Blueprint declarations: `Adw.ActionRow row {` is caught above; bare
    # `ActionRow {` inside a .blp is not, and is left to the reader.
  } | tally "$rel" widget

  # --- css classes ---------------------------------------------------------
  {
    # GtkBuilder: <class name="suggested-action"/>
    grep -ohE '<class +name="[^"]+"' "$f" 2>/dev/null | sed 's/.*name="//; s/"$//'
    # add_css_class ("flat") / add_css_class("flat") — Vala, C, Python, Ruby, JS
    grep -ohE 'add_css_class *\( *"[^"]+"' "$f" 2>/dev/null | sed 's/^[^"]*"//; s/"$//'
    grep -ohE "add_css_class *\\( *'[^']+'" "$f" 2>/dev/null | sed "s/^[^']*'//; s/'$//"
    # css_classes = ["flat", "circular"] / styles ["flat"] (blueprint)
    grep -ohE '(css_classes|styles) *[=:]? *\[[^]]*\]' "$f" 2>/dev/null \
      | grep -ohE '"[^"]+"' | tr -d '"'
  } | tally "$rel" css

  # --- signals -------------------------------------------------------------
  # What the component responds to. Connection sites, not emissions.
  {
    # GtkBuilder: <signal name="clicked" handler="on_clicked"/>
    grep -ohE '<signal +name="[^"]+"' "$f" 2>/dev/null | sed 's/.*name="//; s/"$//'
    # Vala / C / Python / JS: foo.clicked.connect (...), connect("clicked", ...)
    grep -ohE '\.[a-z][a-z0-9_]*\.connect *\(' "$f" 2>/dev/null \
      | sed -E 's/^\.//; s/\.connect *\($//'
    grep -ohE 'connect(_after|_object)? *\( *"[^"]+"' "$f" 2>/dev/null | sed 's/^[^"]*"//; s/"$//'
    # Ruby: signal_connect("clicked") / signal_connect :clicked
    grep -ohE "signal_connect(_after)? *\\(? *[:\"'][A-Za-z0-9_-]+" "$f" 2>/dev/null \
      | sed -E "s/.*[:\"']//"
    # Blueprint: clicked => \$on_clicked()
    grep -ohE '^[[:space:]]*[a-z][a-z0-9_-]* *=> *\$' "$f" 2>/dev/null | sed 's/ *=>.*//'
  } | sed 's/_/-/g' | tally "$rel" signal

  # --- actions -------------------------------------------------------------
  grep -ohE '"(app|win)\.[A-Za-z0-9_.-]+"' "$f" 2>/dev/null | tr -d '"' | tally "$rel" action
done
