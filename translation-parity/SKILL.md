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
carries 78 languages and 15,352 translated strings, contributed over fourteen
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
scripts/catalogue.rb <upstream-tree> --role upstream > upstream-catalogue.yaml
scripts/catalogue.rb <port-tree>     --role port     > port-catalogue.yaml
```

That is the artifact the rest of this skill works on — the format is below,
under **The data format**. Underneath it, `scripts/msgid-census.sh <tree>`
does the extraction and prints one row per *call site*:
`msgctxt<TAB>msgid<TAB>kind<TAB>file:line`, with `-` for no context. Run it
directly when you want to grep the raw scan; the catalogue is what you diff.

The key is the `(msgctxt, msgid)` pair, because that is what gettext looks up
— so `cut -f1,2 | sort -u` over the census is the catalogue and everything
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

### Step 2 — Measure, then diff

```sh
scripts/catalogue.rb --compare upstream-catalogue.yaml port-catalogue.yaml > translation-parity.yaml
```

That computes every number below and writes the comparison document. Read its
`summary:` block first; the rest of this step is what those fields mean and
how to check them by hand when you distrust one.

The report carries five metrics. Take all five; they answer different
questions and only the first one is the pass condition.

```sh
cut -f1,2 upstream-msgids.tsv | sort -u > up.keys
cut -f1,2 port-msgids.tsv     | sort -u > port.keys

wc -l < up.keys                                  # 1. messages (distinct keys)   217
wc -l < upstream-msgids.tsv                      # 2. occurrences (call sites)   260
ls up/po/*.po | wc -l                            # 3. languages                   78
ruby scripts/catalogue.rb up --role upstream     # 4. translated strings      15,352
cut -f1,2 upstream-msgids.tsv | sort | uniq -c | sort -rn   # 5. uses per message
```

**1 — messages.** The catalogue size, and the only number parity is defined
on. gettext is a hash table: one entry per `(msgctxt, msgid)` key however many
call sites reach it.

```sh
comm -23 up.keys port.keys | wc -l    # gaps: upstream messages the port does not produce
comm -13 up.keys port.keys | wc -l    # extra: port messages nobody has translated
comm -12 up.keys port.keys | wc -l    # ported
```

**2 — occurrences.** 260 against 217 means 19 messages are reused. Report both
numbers and the gap between them, per message, in the `Uses` column. It is
what tells you a message is load-bearing: `_Cancel` is nine call sites, so it
is nine places the port can drop it, and a port at `9 → 2` has seven
untranslated buttons that the key-set diff will never show, because the key is
present. That is a real finding and it belongs in the report.

**It is a finding, not a pass condition.** Do not require `port uses ==
upstream uses`. The count asserts something about the port's *structure* —
how many dialogs it builds, whether its cancel buttons come from one shared
helper — which is `COMPONENT_PARITY.md`'s question and is answered there per
component. Made a translation condition it fails both ways: a port that builds
nine cancel buttons through one helper reads `1 → 9` and is correct, and a
port that pads its literals to nine passes while nothing changed. So a `Uses`
mismatch opens an investigation and, where it turns out to be a missing call
site, a **component** row — never a translation row that the key set says is
`ported`.

**3 and 4 — languages and translated strings.** These are the inherited asset,
and the port either carries them or destroys them. 78 and 15,352 go in the
header as a pair with what the port ships, because `0 of 78` is the headline
finding of an untranslated port and a raw message count hides it completely.
Count `.po` files rather than trusting `LINGUAS` — a language present in one
and not the other is itself a defect, and `diff` is the check:

```sh
diff <(ls up/po/*.po | xargs -n1 basename -s .po | sort) <(sort up/po/LINGUAS)
```

Take the translated-string count from `catalogue.rb` rather than counting
`msgstr` lines. `grep -c '^msgstr'` over gnome-contacts' `po/` gives 15,703,
which is 351 too many and wrong three separate ways: it counts the 78 file
headers, which hold `Plural-Forms` and a translator name rather than a
translation; it counts the 273 entries whose `msgstr` is empty as translated;
and `grep -c '^msgstr "..*"'` — the obvious correction — swings 600 the other
way, because a long translation is written as `msgstr ""` followed by
continuation lines and so looks empty on its first line. The right number for
gnome-contacts is **15,352 translated and 273 untranslated over 15,625
entries**, and those three figures reconcile. Report one that does.

**5 — uses per message**, sorted descending, is the porting order. Work down
it and the port's most-repeated strings land first.

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

### The data format

Two documents, both **generated and never hand-edited**. They hold facts a
machine can recompute; the judgements it cannot recompute — why a gap is open,
which component it waits on, what a reviewer decided — live in
`TRANSLATION_PARITY.md`. Regenerating the YAML must never destroy anything, so
nothing that matters may only exist there.

Both are sorted by `(ctxt, id)`, so plain `diff` over two of them is readable
without the compare step.

#### `<role>-catalogue.yaml` — one tree

```yaml
version: 1
tree:
  role: upstream            # upstream | port
  path: up
  ref: main
  sha: 86f14e6a
  scanned: '2026-09-20'
domain: gnome-contacts      # meson.project_name(), or the Rakefile's task.domain
totals:
  messages: 217             # distinct (ctxt, id) keys - the catalogue size
  occurrences: 260          # call sites
  reused: 19                # messages with more than one call site
  plural: 8
  with_context: 11
languages:
  count: 78                 # .po files, not LINGUAS
  translated_strings: 15352
  untranslated_strings: 273
  linguas_matches_files: true
  only_in_linguas: []       # present only when non-empty
  only_in_po_files: []
  list: [ab, af, ar, ...]
messages:
  - id: Export
    kind: single            # single | plural
    uses: 1
    sites: ['data/ui/contacts-main-window.blp:77']
  - ctxt: shortcut window   # omitted entirely when the message has no context
    id: Open menu
    kind: single
    uses: 1
    sites: ['data/ui/contacts-shortcut-dialog.blp:16']
```

`ctxt` is **absent**, not empty, when a message has no context — so a key is
`[ctxt, id]` with a real nil, and no msgid beginning with a sentinel character
can collide with a real context. `uses` and `sites` are outside the identity
on purpose: two trees that reach one key a different number of times still
hold the same message.

`po/` is excluded from `messages:` even though the census scans it. A `.po`
lists every msgid the last `msgmerge` knew about, deleted ones included, so
counting it would report a tree as emitting strings its code no longer has.
The po files are read for `languages:` and nothing else.

#### `translation-parity.yaml` — the comparison

```yaml
version: 1
upstream: {role: upstream, ref: main, sha: 86f14e6a, domain: gnome-contacts,
           messages: 217, occurrences: 260, reused: 19, plural: 8, with_context: 11}
port:     {role: port, ref: ruby, sha: 13b5ba33, domain: null,
           messages: 0, occurrences: 0, reused: 0, plural: 0, with_context: 0}
summary:
  ported: 0
  gaps: 217
  extra: 0                  # port keys upstream never had - untranslated by definition
  kind_mismatch: 0          # same key, plural one side and single the other
  uses_mismatch: 0          # same key, different number of call sites
  occurrences: {upstream: 260, port: 0}
  languages: {upstream: 78, port: 0}
  languages_missing: [ab, af, ar, ...]
  domain_matches: false
  parity: false
messages:
  - id: Export
    state: ported           # ported | gap | extra
    kind: {upstream: single, port: single}
    uses: {upstream: 1, port: 1}
    upstream_sites: ['data/ui/contacts-main-window.blp:77']
    port_sites: ['lib/main.rb:212']
  - ctxt: shortcut window
    id: Open menu
    state: gap
    kind: {upstream: single, port: null}
    uses: {upstream: 1, port: 0}
    upstream_sites: ['data/ui/contacts-shortcut-dialog.blp:16']
    text_owed: Open menu    # present only on gaps: the byte-identical English
```

`summary.parity` is the single boolean, and it is true only when there are no
gaps, no `kind_mismatch`, no missing language and the domain matches. Note
what is **not** in it: `uses_mismatch` and `extra`. Both are reported on every
run and neither blocks parity — `uses_mismatch` is a component question
(Step 2, metric 2) and `extra` is a list of strings the port owes translators,
not strings it owes upstream. A checker that failed on either would be failing
on the wrong ledger's business.

`text_owed` exists so that closing a gap is transcription. Copy it; never
retype it.

### Step 3 — Write the ledger

`TRANSLATION_PARITY.md` at the root of the port's `ruby` branch. Its tables
render `translation-parity.yaml` — the counts, states, kinds, uses and sites
all come from the generated document, so do not maintain them by hand and do
not let the two disagree. What the markdown adds is everything the YAML cannot
carry: the grouping by upstream source file, and the sentence per gap saying
what it waits on.

It is the contract, not a summary of one. Commit both files.

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
| Upstream occurrences | 260 across 217 messages (19 reused) |
| Port occurrences | 0 |
| Upstream languages | 78 `.po` files, 15,352 translated strings |
| Languages shipped by the port | 0 |
| Build command | `rake gettext:mo` |

## src/contacts-main-window.vala → lib/main.rb (38 messages)

| # | msgctxt | msgid | Kind | Uses | Port site | State |
|---|---|---|---|---|---|---|
| 1 | — | `Export` | single | 1 → 1 | `lib/main.rb:212` `_("Export")` | ported |
| 2 | — | `%llu Selected` | plural | 1 → 1 | `lib/main.rb:180` `n_("%llu Selected", "%llu Selected", n)` | ported |
| 3 | — | `_Cancel` | single | 9 → 2 | `lib/crop_dialog.rb:44`, `lib/import_dialog.rb:71` | ported ⚠ |
| 4 | shortcut window | `Open menu` | single | 1 → 0 | — | **gap** |
```

`Uses` is `<upstream call sites> → <port call sites>`, from metric 2. Row 3 is
`ported` — the key is in the catalogue, which is what translation parity
asks — and it is flagged, because seven of the nine buttons are somewhere
else or nowhere. Chase it in `COMPONENT_PARITY.md`; the flag comes off when
that ledger accounts for all nine, whether as nine components or as one
helper used nine times.

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

Parity is proven when all three hold:

- `summary.parity` is `true` in a freshly regenerated `translation-parity.yaml`
  — which is gaps `0`, `kind_mismatch` `0`, `languages_missing` empty and
  `domain_matches` true, all at once;
- `msgfmt`/`rmsgfmt` compiles every `.po` without error, and the port's build
  target installs one `.mo` per language;
- the app runs under a non-English locale and shows translated text —
  `LANGUAGE=de LC_ALL=de_DE.UTF-8 <port binary>`, driven headless per
  `ruby-gtk-testing`, asserting on one known string.

Regenerate before reading; a `parity: true` from an old run proves the state
of an old tree. The compare step is cheap and has no excuse not to be rerun.

The last check is not optional and is the only one that is not a document.
A correct catalogue that is never bound, or is bound to the wrong path,
produces an app that is 100% translated on paper and entirely English on
screen, and `summary.parity` will say `true` the whole time.

Report every metric, not an adjective — and report them as pairs against
upstream, because a lone number cannot be read:

```
217/217 messages · 260/260 occurrences · 78/78 languages · 15,352 strings · de verified on screen
```

That is a claim someone can re-run. "Fully localised" is not. Occurrences are
reported even though they are not the pass condition: `217/217 · 190/260` is a
port that has the whole catalogue and is missing 70 call sites, which the
message count alone reads as finished.

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

That is **260 occurrences** over **217 distinct keys**: 19 messages are reused,
led by `_Cancel` at nine call sites, `Contacts` at six, `Select a Contact` and
`_Done` at five. Of the 217, **8 are plurals** and **11 carry a msgctxt**, all
of them `"shortcut window"`.

`po/` holds **78** `.po` files and **15,352** translated strings, and `LINGUAS`
matches the file list exactly. Completeness ranges from `eu` at 100% through
`fr` at 94% to `ab` at 22% — all 78 ship, because untranslated entries fall
back to the msgid and a deleted language starts its next contributor at zero.

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
- Never hand-edit the YAML. It is generated; anything written there is lost on
  the next run, which makes it the worst possible place to record a decision.
  Decisions go in `TRANSLATION_PARITY.md`.
- Never make the occurrence count a pass condition, and never leave it out of
  the report. It is the metric that finds a dropped call site behind a key the
  catalogue already has; it is not a statement about the catalogue. Equal keys
  decide parity, unequal uses open a component investigation.
- Never drop a language because its `.po` is 22% translated. Partial is what
  gettext is built for — untranslated entries fall back to the msgid — and a
  language deleted from `LINGUAS` is a language whose next contributor starts
  from nothing.
- Extra port messages are allowed, listed under `## Extra`, and never counted
  as parity. Each one is English-only until somebody translates it; say so.
- A marked string in a widget the port has not built yet is a gap that waits on
  a component gap. Name the component; do not close the row.
