#!/usr/bin/env bash
# Census the translatable messages in a source tree, one row per message.
#
# Output: <msgctxt>\t<msgid>\t<kind>\t<file>:<line>
#         msgctxt is `-` when the message has none.
#
# The (msgctxt, msgid) pair is gettext's lookup key, so it is the unit here -
# not the source line, not the .po entry. Two calls to _("Cancel") in two files
# are one message and one row; C_("shortcut window", "Help") and _("Help") are
# two messages that a human reader would call the same string.
#
# `kind` says which marker produced the row, so a message that is plural
# upstream and singular in the port shows up as a difference on a key that
# otherwise matches:
#
#   single   _("...")            N_("...")          translatable="yes"
#   plural   ngettext(a, b, n)   n_(a, b, n)        Nn_ / np_
#   po       an msgid already in po/*.po - what translators have been given
#
# Usage: msgid-census.sh <tree> [more-trees...]
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: $(basename "$0") <tree>..." >&2; exit 2; }

# A string is translatable only if a marker wraps it, so there is no file-type
# gate here the way there is in test-census.sh - every file that can hold a
# marker is read, and files that hold none cost nothing.
sources() {
  find "$1" -type f \
    -not -path '*/.git/*' -not -path '*/_build/*' -not -path '*/build/*' \
    -not -path '*/node_modules/*' -not -path '*/vendor/*' \
    -not -path '*/subprojects/*' -not -path '*/.bundle/*' \
    -not -path '*/.claude/skills/*' -not -path '*/target/*' \
    \( -name '*.vala' -o -name '*.c' -o -name '*.cpp' -o -name '*.h' \
       -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.rs' \
       -o -name '*.rb' -o -name '*.blp' -o -name '*.ui' -o -name '*.xml' \
       -o -name '*.xml.in' -o -name '*.xml.in.in' \
       -o -name '*.desktop.in' -o -name '*.desktop.in.in' \
       -o -name '*.po' -o -name '*.pot' \) 2>/dev/null
}

for tree in "$@"; do
  TREE=${tree%/}
  sources "$TREE" | while IFS= read -r f; do
    rel=${f#"$TREE"/}
    case "$f" in

      # ---------------------------------------------------------------- .po
      # The po files are the only place the *shipped* message set is recorded,
      # and reading them needs no gettext tooling. msgid and msgctxt may be
      # split over continuation lines ("" then several "..." lines), so this
      # accumulates rather than matching one line.
      *.po|*.pot)
        awk -v F="$rel" '
          function flush(   k) {
            if (id != "" ) {
              print (ctxt == "" ? "-" : ctxt) "\t" id "\t" (plural ? "plural" : "po") "\t" F ":" line
            }
            id = ""; ctxt = ""; plural = 0; state = ""
          }
          function body(s) { sub(/^[^"]*"/, "", s); sub(/"[[:space:]]*$/, "", s); return s }
          /^msgctxt[[:space:]]/ { flush(); state = "c"; ctxt = body($0); line = NR; next }
          /^msgid[[:space:]]/   { if (state != "c") flush(); state = "i"; id = body($0); line = NR; next }
          /^msgid_plural[[:space:]]/ { plural = 1; state = "p"; next }
          /^msgstr/             { state = "s"; next }
          /^[[:space:]]*"/      { if (state == "c") ctxt = ctxt body($0); else if (state == "i") id = id body($0); next }
          /^[[:space:]]*$/      { flush(); next }
          { }
          END { flush() }
        ' "$f" ;;

      # ------------------------------------------------- GtkBuilder / XML-ish
      # translatable="yes" marks the *element text*, with the context in a
      # sibling context= or comments= attribute. Handled statefully because
      # GtkBuilder wraps long labels onto the next line.
      *.ui)
        awk -v F="$rel" '
          {
            if (match($0, /translatable="(yes|true)"/)) {
              ctxt = "-"
              if (match($0, /context="[^"]*"/)) {
                ctxt = substr($0, RSTART + 9, RLENGTH - 10)
              }
              rest = $0; sub(/^.*translatable="(yes|true)"[^>]*>/, "", rest)
              if (rest ~ /</) { sub(/<.*$/, "", rest); if (rest != "") print ctxt "\t" rest "\tsingle\t" F ":" NR }
              else { open = 1; buf = rest; ln = NR; oc = ctxt }
              next
            }
            if (open) {
              buf = buf $0
              if (buf ~ /</) { sub(/<.*$/, "", buf); if (buf != "") print oc "\t" buf "\tsingle\t" F ":" ln; open = 0 }
            }
          }' "$f" ;;

      # metainfo / appstream / gschema: the whole point of the .in suffix is
      # that meson runs i18n.merge_file over it, so every <name>, <summary>,
      # <p>, <li>, <caption> and gschema <summary>/<description> is a message.
      *.xml|*.xml.in|*.xml.in.in)
        # Whole file as one string, then pull the text of each translatable
        # element - metainfo <name>/<summary>/<p>/<li>/<caption> and gschema
        # <summary>/<description>. Read this way because those elements wrap
        # over several lines far more often than not, and a line-at-a-time
        # scan silently drops every paragraph longer than 80 columns.
        #
        # <release> notes are NOT extracted: the AppStream ITS rules xgettext
        # applies mark them untranslatable, and a scanner that takes them
        # reports hundreds of phantom messages for an app with a long history.
        tr '\n' ' ' < "$f" \
        | sed -E 's|<releases>.*</releases>| |g; s|<release[ >][^<]*<\/release>| |g' \
        | grep -oE '<(name|summary|description|p|li|caption)( [^>]*)?>[^<]+</' \
        | grep -v 'translat[a-z]*="no"' \
        | sed -E 's|^<[a-z]+( [^>]*)?>||; s|</$||; s|[[:space:]]+| |g; s|^ ||; s| $||' \
        | while IFS= read -r m; do
            [ -n "$m" ] && printf -- '-\t%s\tsingle\t%s\n' "$m" "$rel"
          done ;;

      # .desktop.in - Name/GenericName/Comment/Keywords are the translated
      # keys. The old `_Name=` intltool spelling is still in some trees.
      # Keywords is one message, semicolons and all, and it carries a
      # translator comment telling translators not to touch them.
      *.desktop.in|*.desktop.in.in)
        grep -nE '^_?(Name|GenericName|Comment|Keywords|X-GNOME-FullName)=' "$f" 2>/dev/null \
        | while IFS=: read -r line rest; do
            printf -- '-\t%s\tsingle\t%s:%s\n' "${rest#*=}" "$rel" "$line"
          done ;;

      # ------------------------------------------------------------- markers
      # One awk over every code and blueprint file. The marker set is the union
      # of what Vala/C, blueprint, Python, GJS, Rust and the Ruby `gettext` gem
      # use, because a port and its original are being compared and both must
      # be read by the same rules.
      #
      #   _(  N_(  gettext(               -> single
      #   C_(  NC_(  pgettext(  p_(  np_( -> single, with context
      #   ngettext(  n_(  Nn_(            -> plural, key is the singular
      #
      # Only the first string literal after the marker is taken, which is the
      # msgid in every one of those forms except the context ones, where the
      # first is the context and the second is the msgid.
      *.vala|*.c|*.cpp|*.h|*.py|*.js|*.ts|*.rs|*.rb|*.blp)
        awk -v F="$rel" '
          function unq(s) { return s }
          {
            line = $0
            # Whole-line comments only: a marker inside a trailing comment is
            # rare, and stripping // mid-line would eat URLs and C escapes.
            if (line ~ /^[[:space:]]*(\/\/|#|\*|--)/) next
            pos = 1
            while (match(substr(line, pos), /(^|[^A-Za-z0-9_.])(_|N_|NC_|C_|n_|Nn_|np_|p_|s_|ngettext|d?n?p?gettext|pgettext2?)[[:space:]]*\(/)) {
              start = pos + RSTART - 1
              m = substr(line, start, RLENGTH)
              sub(/^[^A-Za-z_]/, "", m); sub(/[[:space:]]*\($/, "", m)
              pos = start + RLENGTH
              rest = substr(line, pos)

              # first literal
              if (!match(rest, /^[[:space:]]*"([^"\\]|\\.)*"/)) continue
              a = substr(rest, RSTART, RLENGTH); sub(/^[[:space:]]*"/, "", a); sub(/"$/, "", a)
              rest2 = substr(rest, RSTART + RLENGTH)

              ctxt = "-"; id = a; kind = "single"
              if (m == "C_" || m == "NC_" || m == "p_" || m == "np_" || m ~ /^d?n?pgettext/) {
                if (!match(rest2, /^[[:space:]]*,[[:space:]]*"([^"\\]|\\.)*"/)) continue
                b = substr(rest2, RSTART, RLENGTH); sub(/^[^"]*"/, "", b); sub(/"$/, "", b)
                ctxt = a; id = b
                if (m == "np_") kind = "plural"
              } else if (m == "ngettext" || m == "n_" || m == "Nn_") {
                kind = "plural"
              } else if (m == "s_") {
                # s_("ctx|msgid") - the context is inside the literal
                if (index(a, "|")) { ctxt = substr(a, 1, index(a, "|") - 1); id = substr(a, index(a, "|") + 1) }
              }
              if (id != "") print ctxt "\t" id "\t" kind "\t" F ":" NR
            }
          }' "$f" ;;
    esac
  done
done | sort -u
:
