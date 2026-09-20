#!/usr/bin/env bash
# Inventory the UI components of a GTK app, per file.
#
# Output: <file>\t<kind>\t<value>\t<count>
#   kind = widget  a Gtk/Adw type instantiated or declared in that file
#          css     a CSS class attached to a widget in that file
#          signal  a signal that file connects a handler to
#          action  a GAction name installed or referenced in that file
#
# Per file, not per instance: grep cannot reconstruct a widget tree. Note that
# one component is often TWO upstream files - a source file plus its .ui/.blp
# template - which the Ruby port merges into one. Union the rows of the mapped
# files before comparing; see the component-parity skill.
# The counts carry multiplicity: three AdwActionRows in a file is
# `widget Adw.ActionRow 3`. A widget built by a shared factory called from
# three places counts once here and three times on screen - read the file.
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
    -not -path '*/.claude/skills/*' -not -path '*/target/debug/*' \
    -not -path '*/test/*' -not -path '*/tests/*' -not -path '*/spec/*' \
    \( -name '*.ui' -o -name '*.blp' -o -name '*.vala' -o -name '*.c' \
       -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.rs' \
       -o -name '*.rb' \) 2>/dev/null
}

# tally <file> <kind> - reads matched values on stdin, emits deduped rows with
# counts. `awk NF` rather than `grep -v` so that empty input is not a failure
# exit under pipefail.
tally() {
  sed 's/^ *//; s/ *$//' | awk 'NF' | sort | uniq -c \
    | awk -v f="$1" -v k="$2" '{c=$1; $1=""; sub(/^ /,""); print f "\t" k "\t" $0 "\t" c}'
}

srcfiles | while IFS= read -r f; do
  rel=${f#"$TREE"/}

  # --- widgets -------------------------------------------------------------
  # Normalised to Ns.Type so that Vala `new Adw.ActionRow`, GtkBuilder
  # class="AdwActionRow", gtk-rs `adw::ActionRow` and Ruby
  # `Adwaita::ActionRow.new` all land on the same value.
  {
    # GtkBuilder objects AND template roots: <template parent="AdwBin">.
    # An app-defined template class (class="MyWidget") is deliberately not a
    # row - resolve it to the file that defines it. See the skill, Step 3.
    grep -ohE '(class|parent)="(Adw|Gtk|Vte|GtkSource|Shumate|WebKit|Panel)[A-Za-z0-9]+"' "$f" 2>/dev/null \
      | sed -E 's/.*"(Adw|Gtk|Vte|GtkSource|Shumate|WebKit|Panel)([A-Za-z0-9]+)"/\1.\2/'
    # Vala, Python, GJS, blueprint: Adw.ActionRow
    grep -ohE '\b(Adw|Gtk|Adwaita|Vte|GtkSource|Shumate|WebKit|Panel)\.[A-Z][A-Za-z0-9]+' "$f" 2>/dev/null \
      | sed -E 's/^Adwaita\./Adw./'
    # Ruby: Adwaita::ActionRow / Gtk::Box
    grep -ohE '\b(Adw|Gtk|Adwaita|Vte|GtkSource|Shumate|WebKit|Panel)::[A-Z][A-Za-z0-9]+' "$f" 2>/dev/null \
      | sed -E 's/::/./; s/^Adwaita\./Adw./'
    # gtk-rs: lowercase crate modules - gtk::Button, adw::Carousel - including
    # inside TemplateChild<gtk::Button>, which is an instance site.
    grep -ohE '\b(gtk4?|adw|libadwaita|vte|sourceview5?|shumate|webkit6?|panel)::[A-Z][A-Za-z0-9]+' "$f" 2>/dev/null \
      | sed -E 's/^gtk4?::/Gtk./; s/^(adw|libadwaita)::/Adw./; s/^vte::/Vte./
                s/^sourceview5?::/GtkSource./; s/^shumate::/Shumate./
                s/^webkit6?::/WebKit./; s/^panel::/Panel./'
    # Blueprint bare declarations. `using Gtk 4.0` makes Gtk the implicit
    # namespace, so the whole widget tree is written unprefixed - `Box {`,
    # `MenuButton btn {`, `content: WindowHandle {`. Without this the only
    # widgets found in a .blp are the Adw.-prefixed ones, which on a typical
    # app is four rows out of thirty.
    case "$f" in *.blp)
      {
        grep -ohE '^[[:space:]]*[A-Z][A-Za-z0-9]+([[:space:]]+[a-z_][A-Za-z0-9_]*)?[[:space:]]*\{' "$f" 2>/dev/null \
          | sed -E 's/^[[:space:]]*([A-Z][A-Za-z0-9]+).*/\1/'
        grep -ohE '[a-z][a-z0-9_-]*:[[:space:]]*[A-Z][A-Za-z0-9]+[[:space:]]*\{' "$f" 2>/dev/null \
          | sed -E 's/.*:[[:space:]]*([A-Z][A-Za-z0-9]+).*/\1/'
      } | sed 's/^/Gtk./' ;;
    esac
  } | grep -vxE 'Gtk\.Template' | tally "$rel" widget

  # --- css classes ---------------------------------------------------------
  {
    # GtkBuilder: <class name="suggested-action"/>
    grep -ohE '<class +name="[^"]+"' "$f" 2>/dev/null | sed 's/^[^"]*"//; s/"$//'
    # add_css_class ("flat") - Vala, C, Python, Ruby, JS, Rust
    grep -ohE 'add_css_class *\( *"[^"]+"' "$f" 2>/dev/null | sed 's/^[^"]*"//; s/"$//'
    grep -ohE "add_css_class *\( *'[^']+'" "$f" 2>/dev/null | sed "s/^[^']*'//; s/'$//"
    # css_classes = ["flat"] / styles ["flat"] (blueprint) /
    # .css_classes(vec!["flat"]) and .set_css_classes(&["flat"]) (gtk-rs).
    # Blueprint normally breaks these across lines, so the bracket is tracked
    # with a state machine rather than matched on one line.
    awk '/(^|[^A-Za-z_])(set_)?(css_classes|styles)[[:space:]]*[=:(]?[[:space:]]*(vec!)?[[:space:]]*&?[[:space:]]*\[/ { s = 1 }
         s { print; if (/\]/) s = 0 }' "$f" 2>/dev/null \
      | grep -ohE '"[^"]+"' | tr -d '"'
  } | tally "$rel" css

  # --- signals -------------------------------------------------------------
  # What the component responds to. Connection sites, not emissions.
  {
    # GtkBuilder: <signal name="clicked" handler="on_clicked"/>
    grep -ohE '<signal +name="[^"]+"' "$f" 2>/dev/null | sed 's/^[^"]*"//; s/"$//'
    # Vala / C / Python / JS: foo.clicked.connect (...)
    grep -ohE '\.[a-z][a-z0-9_]*\.connect *\(' "$f" 2>/dev/null \
      | sed -E 's/^\.//; s/\.connect *\($//'
    # connect("clicked", ...) / connect_after('clicked')
    grep -ohE 'connect(_after|_object)? *\( *"[^"]+"' "$f" 2>/dev/null | sed 's/^[^"]*"//; s/"$//'
    # Ruby: signal_connect("notify::position") - the detail is part of the
    # signal, so ':' stays inside the character class.
    grep -ohE "signal_connect(_after)? *\(? *[:\"'][A-Za-z0-9_:-]+" "$f" 2>/dev/null \
      | sed -E "s/.*signal_connect(_after)? *\(? *[:\"']//"
    # gtk-rs: b.connect_clicked(...), connect_notify_local(Some("position"), ..)
    grep -ohE 'connect_notify(_local)? *\( *Some\( *"[^"]+"' "$f" 2>/dev/null \
      | sed 's/^[^"]*"//; s/"$//; s/^/notify::/'
    grep -ohE '\bconnect_[a-z0-9_]+ *\(' "$f" 2>/dev/null \
      | grep -vE 'connect_notify' | sed -E 's/^connect_//; s/ *\($//'
    # Blueprint: clicked => $on_clicked()
    grep -ohE '^[[:space:]]*[a-z][a-z0-9_-]* *=> *\$' "$f" 2>/dev/null | sed 's/ *=>.*//'
  } | sed 's/_/-/g' | tally "$rel" signal

  # --- actions -------------------------------------------------------------
  # Prefixed names in quotes (source) or in GtkBuilder element text
  # (<property name="action-name">win.next-page</property>), plus the bare
  # names registered at an install site - a port commonly builds 'start-tour'
  # and lets the widget supply the `win.` prefix, so the literal never appears.
  {
    grep -ohE "['\"](app|win)\.[A-Za-z0-9_.-]+['\"]" "$f" 2>/dev/null | tr -d "\"'"
    grep -ohE '>(app|win)\.[A-Za-z0-9_.-]+<' "$f" 2>/dev/null | tr -d '><'
    grep -ohE '(SimpleAction\.new|install_action|add_action|create_action|lookup_action|action_name) *[(=:] *["'"'"'][A-Za-z0-9_.-]+' \
      "$f" 2>/dev/null | sed -E 's/.*["'"'"']//'
  } | tally "$rel" action

  :
done
:
