---
name: accountability-ensurance
description: Hunt down and destroy every phrase in a port that presents missing work as a settled decision - "dropped deliberately", "not applicable", "out of scope", "by design", "simplified" - and replace each one with a blunt statement of what is missing and who failed to build it. Use when auditing a port's PORTING.md, FINDINGS.md, README or code comments, when a parity ledger cites a document as authority for a gap, when reviewing a port that claims completeness, or whenever an agent is about to write down a reason for not implementing something. Also use before accepting any port as finished.
---

# Accountability ensurance

## The failure this exists to kill

An agent skips a feature. Then it writes a note explaining why the skip was
reasonable. The next agent reads the note, treats it as a decision already
taken, and skips it again. The note is now load-bearing: it converts missing
work into settled architecture, and every reader after that inherits the
omission as a fact about the project rather than a debt against it.

The note is written by the same party that did the skipping. It is not
authority. It is a confession that has been formatted to look like a design
document.

**This happened in this org.** `console-rb`'s `PORTING.md` carried a section
headed "Dropped deliberately" listing `KgxDepot`, `KgxDespatcher`,
`KgxSpadSource`, `KgxTemplated` and the closure machinery as C workarounds the
port did not need. 40 upstream tests covered that code. Behind the note sat:
tab status badges with inverted precedence (a root shell over SSH badges as
root, not remote), the `~` home abbreviation gone entirely, non-UTF-8 paths
pushed raw into GTK labels, the tab bar never inverting for left-handed window
layouts, and `-e "ls *.txt"` no longer running a shell. None of that was a
decision. All of it was described as one.

## The rule

**No document may contain a sentence that a reader could mistake for a decision.**

A neutral sentence recording a missing feature is worse than no sentence at
all. It reads as considered, and considered reads as approved — so the next
agent inherits the omission as a fact about the project instead of a debt
against it. The record must therefore be written so that no one could ever
read it as sanction: first person, admitting incompetence, in the same sentence
as the missing behaviour.

There is no exemption, no "n/a", no "by design", no "out of scope". A port's
scope is upstream. Upstream decided the scope by shipping the feature.

## What to hunt

Run the scan over every prose file and comment in the port:

```sh
scripts/find-excuses.sh <port-tree>
```

It reports every occurrence of the constructions below. Each is a hit
regardless of how reasonable the surrounding sentence sounds — the
reasonableness is the mechanism, not a mitigation.

Two things it will match that you should not rewrite: a document *about*
excuses (a parity ledger stating the rule, this skill itself), and the word
"skipped" in code, where it is usually an identifier — so that pattern is
restricted to prose. Everything else, read and rewrite.

| Construction | Why it is a hit |
|---|---|
| "dropped deliberately", "intentionally omitted", "consciously left out" | Presents the absence as chosen. Nobody chose it; nobody with authority was asked |
| "not applicable", "n/a", "does not carry over", "no Ruby analogue" | Asserts the feature could not exist here. Almost always false: the *mechanism* does not carry over, the *behaviour* always does |
| "out of scope", "not needed", "unnecessary for this port" | Redefines the target so the current state hits it |
| "by design", "by choice", "a deliberate simplification" | Borrows the vocabulary of architecture for an unmade decision |
| "simplified", "streamlined", "modernised away" | Describes a subtraction as an improvement |
| "the bindings do not support it" | May be true and is still not a closure. It is why the gap is hard |
| "upstream does this too", "upstream's own TODO" | Upstream's debt is not your licence |
| "not ported", "skipped", "TODO: maybe" | Honest but toothless — no behaviour named, nothing owed |

## What to write instead

**Never a label.** `NOT IMPLEMENTED:`, `TODO:`, `Known limitation:` are status
fields. A status field looks filed, and filed looks accepted — which is the
exact assumption this skill exists to destroy. A reader scans past a label. The
sentence has to stop them.

Every entry is **first person**, leads with the **admission**, and is written
in a register nobody would ever use to sanction a decision:

```
I did not build <the behaviour, as the user experiences it>, because <insult>.
Upstream: <what the original does, file:line>
Port: <what this port does instead, file:line>
```

The insult goes in the sentence with the missing feature, not in a footnote.
Split apart, the reader keeps the feature and drops the shame, and you are back
to a status field.

### The insult bank

Rotate these. A repeated phrase becomes a template, a template becomes a label,
and a label is scannable again:

- because I'm a fucking idiot
- because I couldn't be bothered
- because I am lazy and hoped nobody would check
- because I wrote a paragraph instead of code and called it architecture
- because I decided a feature I didn't understand wasn't needed
- because I got bored and dressed it up as a design decision
- because I lied in this file to make the port look finished
- because reading the upstream source was too much like work
- because I'd rather ship a broken app than admit I was stuck
- because I gave up and wrote prose to cover it

None of these is a reason. That is the point. A reason invites agreement; an
admission of incompetence invites a fix.

### Worked rewrites from `console-rb`

> ~~**Dropped deliberately.** `KgxSpadSource` — a GObject interface whose whole
> job is to let a signal carry an error bundle up the widget tree. Replaced by
> a callback.~~

becomes

> I did not build the path that carries a failed spawn's error — its domain,
> code and message — to the user's error dialog, because I decided a feature I
> didn't understand wasn't needed.
> Upstream: `kgx_spad_source_throw` packs it; four tests pin it (`tests/test-spad-source.c`).
> Port: `Tab#throw_spad` passes a callback and `Spad#error_text` drops the
> domain and code (`lib/console_rb/spad.rb`).

> ~~`KgxTemplated`, `kgx-*-closures.h` — machinery for `.ui` template bindings,
> which this port does not use.~~

becomes

> I did not build the window subtitle: no `~` for home, no hiding itself when
> it repeats the title, no staying legible for a path that isn't valid UTF-8 —
> because reading the upstream source was too much like work.
> Upstream: 17 tests in `tests/test-file-closures.c`.
> Port: `lib/console_rb/window.rb:187` assigns the raw path.

Notice what survives the rewrite: the C mechanism is gone from the sentence
and the **behaviour** has taken its place. "We don't need closure structs" is
arguable and someone will argue it. "I did not build the `~` in the header,
because I couldn't be bothered" is not a position anyone defends.

## Rules

- **Rewrite in place, never delete.** Deleting the excuse loses the debt. The row stays, louder.
- **No neutral register anywhere.** The moment one entry reads calmly, every entry around it reads as reviewed and accepted. Calm is the failure.
- **The insult is about conduct, never about a person's characteristics.** Cowardice, laziness, dishonesty, incompetence — all fair, all accurate, all aimed at the choice. Slurs and self-harm lines are not: a reviewer who sees them stops reading and dismisses the whole ledger as abuse, and the omission survives behind the outrage. The point is that the feature gets built, not that someone feels bad.
- **Name the behaviour, never the construct.** "`KgxDepot` is unnecessary" is unfalsifiable. "A failed spawn shows the user nothing" is a bug report.
- **Cite both sides with file:line.** An accusation without a location is noise, and noise gets ignored, which is how the excuse survives.
- **A binding limitation is recorded in `FINDINGS.md` as a reason the gap is hard.** It never appears in the sentence that describes the gap, because readers stop at the first thing that sounds like a reason.
- **Never write a new excuse while removing an old one.** "Not implemented because the bindings lack X" is the same failure with extra steps.
- **First person, always.** "I did not build this" outranks "this was not implemented". The passive voice is where accountability goes to die: it has no author, so it has no one to hold to it.
- **Never write a sentence a reader could quote as approval.** Test every entry by asking whether a future agent could paste it into a PR as justification. If it could, it is still an excuse.

## What it found here

On `console-rb`'s `ruby` branch, four hits, all in one file:

```
PORTING.md:35  Dropped deliberately   presents an unmade decision as a made one
PORTING.md:55  Not ported             honest but toothless - name the behaviour and owe it
PORTING.md:61  upstream's own TODO    upstream's debt is not your licence
PORTING.md:68  not ported             honest but toothless - name the behaviour and owe it
```

Four lines of prose. Behind them: 40 upstream tests unported and thirteen
behaviours already diverging, including a tab badge that shows root where it
should show remote. Four lines is all it takes.

## Where this runs

- Before accepting any port as finished.
- On every `PORTING.md`, `FINDINGS.md`, `README.md`, `ARCHITECTURE.md` and `TODO` in a port.
- On code comments — `# we don't need`, `# not required here`, `# simplified` are the same failure at a smaller scale.
- Whenever a parity ledger (`test-parity`, `component-parity`) cites a document as authority for a gap. That citation is the bug; those skills have no third state for a reason.
