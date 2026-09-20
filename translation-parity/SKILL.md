---
name: translation-parity
description: Establish and prove translation parity between a GNOME app and its Ruby GTK4 port - census the upstream message catalogue msgid by msgid, map each one to a marked Ruby string with the byte-identical msgid, and keep every language upstream already ships. Use when porting an app to Ruby GTK, when asked whether the port is translated / localised / i18n'd, whether the po files still work, "do we have translation parity", when adding user-visible text to a port, when reviewing a port PR that adds strings, or before calling any port finished. Also use when a port looks complete in English and nobody has checked what happened to the other 77 languages.
---

# Translation parity

## What translation parity means

**A port has translation parity when it emits exactly the same message
catalogue as upstream — the same (msgctxt, msgid) keys, byte for byte — and
ships the same languages, so every translation upstream already has keeps
working.**

Three claims, all of which must hold:

1. **The key sets are equal.** Upstream extracts N messages; the port extracts
   the same N. Not "the same strings roughly", not "N minus the ones in files
   we didn't port". The same keys.
2. **Each key is byte-identical.** `"Exported %d contact"` and
   `"Exported #{count} contacts to #{filename}"` are not the same message, and
   the second one has no translation in any of the 78 languages. A msgid is a
   lookup key in a hash table, not a description of a sentence.
3. **The languages come with it.** Upstream's `po/` directory and its
   `LINGUAS` move to the port unchanged, and the port builds and installs a
   `.mo` for each one. A port that marks all its strings and ships no
   catalogues is translated into English.

Parity is a property of the *census diff*, not of how much `_()` appears in the
diff. Marking 217 Ruby strings that say slightly different things than upstream
said produces a port with 217 messages and zero translations.

### Why it is defined this way

A GNOME app's `po/` directory is the largest body of donated human work in the
repository and the only part of it no developer can reproduce. gnome-contacts
carries 78 languages and 15,703 translated strings, contributed over fourteen
years by people who are mostly not programmers and mostly cannot be asked
again. The port inherits all of it for free — *if and only if* its English is
byte-identical to upstream's. One reworded label silently discards 78
translations of that label, and the app still builds, still passes its tests,
and still looks correct to the person who reworded it.

So the check is not "is the port internationalised". It is "does the port's
catalogue key set equal upstream's", because that is the question whose answer
decides whether the donated work survives.

### Nothing authorises a skip

There are exactly two states: **`ported`** (a marked string in the port
produces this exact key) and **`gap`** (anything else). There is no third
state, and no document, decision or rationale can create one.

In particular:

- **"The port isn't ready for i18n yet" is not a state.** It is a gap count.
  Write the count down.
- **"English-only for now" is not a state.** The 78 languages exist today,
  upstream, in the same repository. Shipping without them is a regression the
  port introduced, not a feature it has not reached.
- **A reworded string is a gap, not an improvement.** If the port's wording is
  genuinely better, that is a change to propose upstream, where the
  translators will be asked. Making it in the port alone just deletes their
  work. The row stays a gap until the msgid matches.
- **A string the port marked but whose msgid differs is two gaps**, not one
  pass: the upstream key is missing, and the port has an extra key nobody has
  translated. Both show in the census diff. Record both.
- **There is no `n/a`, no `not applicable`, no `English only`, no
  `i18n deferred`.** Every one of those is a gap wearing a justification.

A message may be *produced* differently in Ruby than in Vala — `n_()` instead
of `ngettext()`, a `format` call instead of `printf`, a Ruby-built widget
instead of a `.blp` label. That is fine and it is still `ported`, because the
key that reaches the catalogue is the same. The distinction that matters is not
how the port marks the string but which key comes out.

## How to establish it

### Step 1 — Census both trees

Work from the upstream branch of the fork — the port's `ruby` branch and the
original share one repo, and `ruby` is an **orphan** branch, so record the
upstream sha in the ledger header rather than deriving one:

```sh
REPO=$(basename -s .git "$(git remote get-url origin)")
UP=$(gh api "repos/ruby-gtk-project/$REPO" --jq '.parent.default_branch')
```

```sh
scripts/msgid-census.sh <upstream-tree> > upstream-msgids.tsv
scripts/msgid-census.sh <port-tree>     > port-msgids.tsv
```

One row per message: `msgctxt<TAB>msgid<TAB>kind<TAB>file:line`, with `-` for
no context. The key is the `(msgctxt, msgid)` pair, because that is what
gettext looks up — so `cut -f1,2 | sort -u` is the catalogue and everything
else is provenance.

The script reads the marker set shared by Vala, C, blueprint, GtkBuilder XML,
Python, GJS, Rust and the Ruby `gettext` gem (`_`, `N_`, `C_`, `NC_`,
`ngettext`, `n_`, `Nn_`, `p_`, `np_`, `s_`, `pgettext`), plus the three
non-code sources nobody remembers: `.desktop.in`
(`Name`/`GenericName`/`Comment`/`Keywords`), AppStream metainfo
(`<name>`/`<summary>`/`<p>`/`<li>`/`<caption>`, excluding `<release>` notes,
which xgettext's ITS rules do not extract) and the GSettings schema
(`<summary>`/`<description>`). In gnome-contacts those three contribute 24 of
217 messages, and a scan of `src/` alone misses all of them.

**Cross-check the upstream census against a real `po` file before you trust
it.** This is the step that makes the number mean something, and it costs one
command, because the `.po` files record what translators were actually handed:

```sh
scripts/msgid-census.sh up/po | awk -F'\t' '$4 ~ /^de\.po/' | cut -f1,2 | sort -u > de.keys
cut -f1,2 upstream-msgids.tsv | sort -u > src.keys
comm -3 de.keys src.keys
```

The two sets will not be identical and **that is the expected result**, because
a `.po` file is a snapshot of the last `msgmerge`. Every line of the difference
must be explainable as one of exactly two things:

- **only in the po** — a string upstream has since deleted. gnome-contacts has
  two (`Can't import: no contacts found`, `Change Addressbook`).
- **only in the source** — a string added since that language was last merged.
  gnome-contacts has four (`Export`, `Exported %d contact`,
  `Imported %u contact`, `Processing contacts…`).

A difference you cannot explain that way is a scanner miss, not a stale
catalogue, and you fix it by reading the file before writing any ledger. Known
under-reports: a msgid built by concatenating literals across lines, and a
marker whose first argument is a variable rather than a literal. Both are
invisible to any regex and both are found by this cross-check.

**Read the output as a lead, not a verdict.** Then open the files. The census
gives you keys; the ledger needs to say what each message is *for*, and
`%d Selected` does not tell you that the app has two of them — `%d Selected`
and `%llu Selected` — because one counts a `GLib.ListModel` and the other
counts an `int`. Port both. Merging them is a gap in disguise.

### Step 2 — Diff

```sh
cut -f1,2 upstream-msgids.tsv | sort -u > up.keys
cut -f1,2 port-msgids.tsv     | sort -u > port.keys
comm -23 up.keys port.keys | wc -l    # gaps: upstream messages the port does not produce
comm -13 up.keys port.keys | wc -l    # extra: port messages nobody has translated
comm -12 up.keys port.keys | wc -l    # ported
```

Then compare `kind` on the shared keys — a message that is `plural` upstream
and `single` in the port is a gap, because the port will show "1 contacts":

```sh
join -t"$(printf '\t')" -j 1 \
  <(awk -F'\t' '{print $1"\x1f"$2"\t"$3}' upstream-msgids.tsv | sort -u) \
  <(awk -F'\t' '{print $1"\x1f"$2"\t"$3}' port-msgids.tsv     | sort -u) \
| awk -F'\t' '$2 != $3'
```

And compare the language sets, which is a `ls`:

```sh
diff <(ls up/po/*.po | xargs -n1 basename) <(ls port/po/*.po | xargs -n1 basename)
```

### Step 3 — Write the ledger

`TRANSLATION_PARITY.md` at the root of the port's `ruby` branch. It is the
contract, not a summary of one.

```markdown
# Translation parity — <app>

| | |
|---|---|
| Upstream | `main` @ `<sha>` |
| Port | `ruby` @ `<sha>` |
| Domain | `gnome-contacts` |
| Upstream messages | 217 |
| Ported | 0 |
| Gaps | 217 |
| Extra (untranslated) | 0 |
| Upstream languages | 78 |
| Languages shipped by the port | 0 |
| Build command | `rake gettext:mo` |

## src/contacts-main-window.vala → lib/main.rb (38 messages)

| # | msgctxt | msgid | Kind | Port site | State |
|---|---|---|---|---|---|
| 1 | — | `Export` | single | `lib/main.rb:212` `_("Export")` | ported |
| 2 | — | `%llu Selected` | plural | `lib/main.rb:180` `n_("%llu Selected", "%llu Selected", n)` | ported |
| 3 | shortcut window | `Open menu` | single | — | **gap** |
```

Group the tables by upstream *source file*, mapped to the port file that
replaced it, the same way `COMPONENT_PARITY.md` groups by component — a flat
table of 217 rows is unreviewable and hides which screen is untranslated.

Gaps carry a seventh column, `Text still owed`, holding the English the port
must emit verbatim. That column is the whole point: it is the byte-identical
string, copied from the census, so that closing the gap is transcription rather
than authorship.

One row per upstream message, forever. Rows are never deleted. The state is
`ported` or `gap`. There is no third state.

Extra port messages — keys the port emits that upstream never had — go in an
`## Extra` section below the tables, outside the count, each with the reason
the port needs a string upstream did not. They are **not** parity work and they
are also **not** free: every one is a string in English only until someone
translates it, so keep the list short and keep it honest.

### Step 4 — Close the gaps

See `references/ruby-gettext.md` for the wiring — the gem, the Rakefile task,
`bindtextdomain`, the install path, and the five Ruby-specific traps
(interpolation, `%llu`, mnemonics, plural forms, class scope). The discipline,
in four lines:

1. Copy upstream's whole `po/` directory into the port unchanged — every `.po`,
   `LINGUAS`, `POTFILES.in` rewritten to the Ruby paths. Do this **first**, not
   last: it makes every subsequent gap closure verifiable.
2. Keep upstream's domain name (`meson.project_name()`, so `gnome-contacts`,
   not `gnome-contacts-rb`). The `.mo` lookup key is the domain; changing it
   orphans the catalogues.
3. For each gap row, transcribe the msgid from the `Text still owed` column
   into the port, byte for byte, inside the right marker. Never retype it.
4. Re-run the census. The row is `ported` when the key appears in
   `port-msgids.tsv`, not when the code looks right.

### Step 5 — Prove it

Parity is proven when all five hold:

- `comm -23 up.keys port.keys` is empty;
- every shared key has the same `kind` in both censuses;
- the port's `po/` holds the same language set as upstream's;
- `msgfmt`/`rmsgfmt` compiles every `.po` without error, and the port's build
  target installs one `.mo` per language;
- the app runs under a non-English locale and shows translated text —
  `LANGUAGE=de LC_ALL=de_DE.UTF-8 <port binary>`, driven headless per
  `ruby-gtk-testing`, asserting on one known string.

That last one is not optional. A correct catalogue that is never bound, or is
bound to the wrong path, produces an app that is 100% translated on paper and
entirely English on screen, and nothing in the first four checks catches it.

Report the numbers, not an adjective. "217/217, 78 languages, `de` verified on
screen" is a claim someone can re-run. "Fully localised" is not.

### When upstream has no translations

Rare for a GNOME app and not a licence to skip the skill. If there is no `po/`
directory and the census of upstream is empty, say exactly that: parity is 0/0,
met trivially, and the port inherits no catalogue. Then say the second half,
because it is the finding: any user-visible string the port adds is
English-only, and the port has no `po/` for anyone to contribute to. Do not
build empty tables.

## How this ledger relates to the others

| File | Source of truth for |
|---|---|
| `PORTING.md` | **what was ported** — the enumerated units, their state, the cursor |
| `TEST_PARITY.md` | **what was tested** — the test census and bijection |
| `COMPONENT_PARITY.md` | **what was built** — the three-axis component comparison |
| `TRANSLATION_PARITY.md` | **what it says, and in how many languages** — this census |
| `FINDINGS.md` | **binding defects** — ruby-gnome bugs and workarounds found en route |

Component parity and translation parity overlap and neither implies the other.
A port can build the identical `Adw.ActionRow` with an identical label string
and still have zero translation parity, because `COMPONENT_PARITY.md` compares
widget type, CSS classes and signals — not whether the label went through
`_()`. Conversely a marked string in a widget the port never built is a
translation row that can never be `ported`; that row waits on the component,
and the ledger says so by naming the component gap in its `Port site` cell.

Cite `FINDINGS.md` from a gap row when a binding defect is *why* a gap is hard
to close. Never let it convert the gap into a pass.

## Worked example — gnome-contacts-rb

Upstream `main` @ `86f14e6` carries **217** distinct messages:

| Source | Rows |
|---|---|
| `src/**/*.vala` | 161 |
| `data/ui/*.blp` | 75 |
| `src/org.gnome.Contacts.gschema.xml` | 11 |
| `data/org.gnome.Contacts.metainfo.xml.in.in` | 10 |
| `data/org.gnome.Contacts.desktop.in.in` | 3 |

(260 rows, 217 unique keys — a string like `_Cancel` appears in several files.)
Of the 217, **8 are plurals** and **11 carry a msgctxt**, all of them
`"shortcut window"`. `po/` holds **78** languages and **15,703** translated
strings; `eu` is at 100%, `fr` at 94%, `ab` at 22%.

The `ruby` branch @ `13b5ba3` has **no `po/` directory**, no gettext dependency,
and the census of it returns **zero rows**. So the ledger opens at
**0/217, 217 gaps, 0 of 78 languages**.

The interesting part is what the port did instead, because it is the failure
mode this skill exists to catch. Of the 217 upstream msgids, only **six**
appear anywhere in the port's Ruby as a literal — `Address Books`, `Home`,
`Mobile`, `Welcome`, `Work`, `Work Fax`. Every other string was rewritten,
and rewritten in the one way that is unrecoverable:

| Upstream | Port |
|---|---|
| `ngettext("Exported %d contact", "Exported %d contacts", n)` | `"Exported #{count} contacts to #{filename}"` |
| `_("Failed to export contacts")` | `"Could not export: #{e.message}"` |

Those Ruby strings cannot be translated at all. Interpolation happens before
`_()` would ever see the string, so the lookup key is different on every call
and matches nothing in any catalogue. Closing these gaps is not "add `_()`
around it" — it is restructuring the call to `format(n_(...), ...)` with
upstream's msgid, which is the work the ledger's `Text still owed` column
exists to make mechanical.

Note also that the port has no `data/` directory at all: no `.desktop`, no
metainfo, no gschema. That is 24 translation gaps that cannot be closed until
those files exist, and it is simultaneously a component-parity finding. The
`Port site` cell for those 24 rows says so.

## Rules

- Never reword an upstream string while porting it. Byte-identical or it is a
  gap. Improvements go upstream, where the translators get asked.
- Never put `#{}` inside a marked string. It is not a translatable message; it
  is a different message on every call.
- Never renumber or reorder a plural. `n_(singular, plural, n)` takes the same
  two msgids upstream used, in the same order, even when English makes one of
  them look redundant.
- Never invent a domain name for the port. The domain is upstream's, because
  the catalogues are upstream's.
- Never count a row `ported` from reading the code. Count it from the census.
- Never drop a language because its `.po` is 22% translated. Partial is what
  gettext is built for — untranslated entries fall back to the msgid — and a
  language deleted from `LINGUAS` is a language whose next contributor starts
  from nothing.
- Extra port messages are allowed, listed under `## Extra`, and never counted
  as parity. Each one is English-only until somebody translates it; say so.
- A marked string in a widget the port has not built yet is a gap that waits on
  a component gap. Name the component; do not close the row.
