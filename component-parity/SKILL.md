---
name: component-parity
description: Prove that a Ruby GTK4 port's UI matches the app it was ported from - the same widgets in the same numbers, carrying the same CSS classes, responding to the same signals and actions. Use when asked whether a port's UI is complete / matches / "looks the same" / "has component parity", when reviewing a port PR that adds UI, when a ported view looks or behaves subtly wrong, or before calling a port unit or a whole port finished. Pairs with test-parity; both are required before a port is done.
---

# Component parity

## What component parity means

**A port has component parity when, for every component the original builds,
the port builds one that is the same on all three axes: the same widget type in
the same number, carrying the same CSS classes, and responding to the same
signals and actions.**

Three axes, and **all three must hold for the same component**:

1. **Count.** The original's file builds three `Adw.ActionRow`s; the port's
   corresponding file builds three. Not two, not four. Widget-by-widget, not
   an app-wide total — an app-wide total can balance a missing dialog against
   an invented one and report parity.
2. **Style.** Each of those rows carries the same CSS classes as its original,
   including the classes applied conditionally at runtime, and the classes
   themselves are defined in the port's stylesheet with the same rules. A
   `Gtk.Button` with `destructive-action` dropped is the wrong button, not a
   styling nit — it is the red Delete that came out grey.
3. **Behaviour.** Each responds to exactly the same signals and fires the same
   actions. Not "has a handler" — the same signal set. A row that upstream
   connects to both `activated` and a long-press gesture, and the port connects
   only to `activated`, is a component with a feature missing, and no screenshot
   will ever show it.

### Why all three, and why per component

Each axis alone fails in a way that looks like success:

| Axis alone | What passes that shouldn't |
|---|---|
| Count only | A grey, inert copy of the app with every widget in place |
| Style only | A pixel-perfect app where nothing responds to clicks |
| Behaviour only | A working app that looks nothing like the original |

And per-component rather than per-app, because parity is a claim about
*correspondence*. Totals cannot distinguish "ported the preferences dialog" from
"ported forty buttons scattered anywhere".

### What is not a parity failure

Ruby bindings rename things, and the port is not obliged to mirror the
original's file layout or class names. These are **correspondences**, resolved
by naming where the thing lives, not gaps:

- `AdwAboutDialog` → `Adwaita::AboutDialog`; `Adw.` and `Adwaita::` are the
  same namespace.
- A `.ui` file's widget tree built in Ruby as memoized methods (the house style
  — see the `ruby-gtk` skill). The port has no `.ui` files, by design.
- One upstream file split across two Ruby files, or merged. The ledger maps
  file to file(s); the axes are then compared over the mapped set.
- A widget replaced by a strictly newer equivalent, where upstream itself is
  behind — `Gtk.Spinner` → `Adw.Spinner`. Record the substitution and the
  reason. Do not make this judgement silently.

A correspondence that is asserted but not located is a gap. "Probably built
somewhere" is not a finding.

## How to prove it

### Step 1 — Inventory both sides

Use the `component-identification` skill on the upstream tree and on the port's
`ruby` branch, scoped to the same unit. Both trees live in the same fork — the
original on its branch, the port on `ruby`:

```sh
# The fork's upstream branch is whatever the parent's default branch is -
# it is not always `main`, and these forks carry release branches too.
UP=$(gh api repos/ruby-gtk-project/$REPO --jq '.parent.default_branch')

# Pin the upstream commit the port was actually taken from, not the tip.
# Otherwise the ledger's "Upstream @ sha" row goes stale every time upstream
# lands a commit, and gaps appear that the port never had a chance to close.
BASE=$(git merge-base "origin/$UP" origin/ruby)

git worktree add --detach ../upstream "$BASE"
git worktree add --detach ../port     origin/ruby
component-scan.sh ../upstream > up.tsv
component-scan.sh ../port     > port.tsv
```

Do the reading step on both sides. A port inventory built only from the scan
will report every memoized widget method correctly and every loop-built widget
wrongly, which is precisely where ports go thin.

### Step 2 — Map file to file

Before comparing anything, write the file mapping for the unit:

```
src/widgets/paginator.rs + data/resources/ui/paginator.ui -> lib/app/paginator.rb
core/Widgets/ItemRow.vala                                 -> lib/app/widgets/item_row.rb
src/Dialogs/Preferences/*.vala                            -> lib/app/dialogs/preferences.rb
```

**The mapping is many-to-many, and usually 2→1.** Upstream splits a component
across its source file and its `.ui`/`.blp` template; the port merges both into
one Ruby file. So before joining anything, *union the rows of every upstream
file on the left of an arrow*:

```sh
awk -F'\t' -v u="src/widgets/paginator.rs|data/resources/ui/paginator.ui" \
  '$1 ~ u {k[$2 FS $3] += $4} END {for (x in k) print x FS k[x]}' up.tsv | sort
```

Compare that union against the port file's rows. Joining file-to-file instead
puts the widget tree on one side and the callbacks on the other, and reports
both halves as missing.

An upstream file with no port file opposite it is the first and largest kind of
gap, and it is found here rather than in any diff.

### Step 3 — Compare on each axis

Per mapped file, per widget:

```sh
# the shape of the comparison, per file and kind
join -t$'\t' -j1 -a1 -a2 \
  <(awk -F'\t' '$1==U && $2=="widget"{print $3"\t"$4}' up.tsv   | sort) \
  <(awk -F'\t' '$1==P && $2=="widget"{print $3"\t"$4}' port.tsv | sort)
```

Read the result as three questions, in this order:

- **Missing** — in upstream, not in the port. A gap unless located elsewhere.
- **Different count** — present on both, different numbers. Usually a repeater
  built for one item instead of a collection, or a conditional branch not
  ported.
- **Extra** — in the port, not upstream. Not automatically a failure (the house
  style may use a `Gtk.Box` where a `.ui` used a template) but every extra is
  explained, because an unexplained extra is usually a widget standing in for
  one that was not understood.

Then the same over `css`, `signal` and `action`.

### Step 4 — Confirm the styling actually renders

The CSS axis has a second half the scan cannot see: a class attached to a
widget does nothing unless the port's stylesheet defines it. For every class in
the unit, check that the rule exists in the port's CSS and says the same thing.
Diff the two stylesheets directly — they are both plain CSS, and this is the one
place where the two sides can be compared literally:

```sh
find ../upstream ../port -name '*.css' -not -path '*/.git/*'
diff <upstream.css> <port.css>
```

Locate them; do not assume a path. The stylesheet may be one file or seven, and
the port frequently relocates it (`data/resources/style.css` upstream,
`data/style.css` in the port).

Ports often copy the stylesheet across verbatim — planify-rb's seven files are
byte-identical to upstream's. When it is, this half of the axis is satisfied
for free, and the whole CSS question collapses to the one the scan answers:
which of those classes does the port actually *attach* to a widget. A copied
stylesheet is not evidence of style parity; it is the reason style gaps in
these ports are attachment gaps, and it makes the `css` stream the axis to read
closely rather than the one to skip.

**Differences that are correspondences, not gaps.** The rule is that a rule
which *differs* is a gap — but judge the rendered result, not the text:

- **Asset URIs.** `url('/org/gnome/Tour/hand-fg.svg')` (a GResource path) against `url('@ASSETS@/hand-fg.svg')` (substituted at build time) is the same rule. gnome-tour-rb differs from upstream on exactly these two lines and has full style parity.
- **Build-time tokens** — `@ASSETS@`, `@datadir@`, `@APP_ID@` — resolve before the CSS is loaded. Resolve them by hand before comparing.
- **Adwaita named colours** — `@accent_bg_color` against a hex literal is a real difference: the named colour follows the user's theme and the literal does not.

Then run the port and look. Screenshot the unit with the `ruby-gtk-testing`
skill and compare against the original running. Colour, spacing and weight are
the things a class carries, and reading a class name tells you none of them.

### Step 5 — Confirm the behaviour actually fires

A connected signal is not a working signal. For each signal in the unit, drive
it with the `ruby-gtk-testing` driver — `button.activate`, `row.emit(:activated)`
— and assert the effect the original has. A handler connected to an empty
method passes every static check there is.

### Step 6 — Write the ledger

`COMPONENT_PARITY.md` at the root of the port's `ruby` branch, one section per
unit, appended to as units land:

```markdown
# Component parity — <app>

| | |
|---|---|
| Upstream | `main` @ `<sha>` |
| Port | `ruby` @ `<sha>` |
| Units with parity | 3 / 27 |

## Unit: item row  —  `core/Widgets/ItemRow.vala` -> `lib/planify/widgets/item_row.rb`

| Widget | Up × | Port × | CSS | Signals | Verdict |
|---|---:|---:|---|---|---|
| `Adw.ActionRow` | 1 | 1 | ✓ `item-row`, `priority-{1..4}` | ✓ `activated` | parity |
| `Gtk.CheckButton` | 1 | 1 | ✓ `circular-check` | ✓ `toggled` | parity |
| `Gtk.Label` | 2 | 1 | — | — | **gap**: due-date label not built |
| `Gtk.GestureLongPress` | 1 | 0 | — | ✗ `pressed` | **gap**: no context menu on long press |

Stylesheet: `priority-3` defined upstream as `color: @orange_3`, port has
`color: @yellow_5`. **gap**.
Driven: check toggles completion ✓, long press does nothing ✗.
Screenshot: `tmp/shots/item-row.png`.
```

A unit has parity when every row says `parity`, the stylesheet line is clean,
and the driven line has no ✗. One gap is not a pass with a note.

## Worked example — planify-rb

The opening whole-app scan:

| Axis | Upstream distinct | Port distinct | In upstream, not in port |
|---|---:|---:|---:|
| Widget types | 144 | 81 | 74 |
| CSS classes | 99 | 33 | 88 |
| Signals | 195 | 29 | 175 |

The signal row is the one to read. The port has 81 of 144 widget types — it
looks more than half built — while connecting 29 of 195 signals. That is the
shape of a port with the UI laid out and the behaviour not yet wired, and it is
exactly the state that a screenshot review passes and a component-parity review
fails.

Among the 74 missing widget types, `Adw.NavigationView`, `Adw.NavigationPage`,
`Adw.BottomSheet` and `Adw.PasswordEntryRow` are whole navigation and
credential flows absent from the port. `Adw.Easing` and
`Adw.DialogPresentationMode` in the same list are enums, not widgets — strike
them, per `component-identification` Step 2.

## Rules

- Never report parity from the scan alone. Steps 4 and 5 are where the axes are
  actually checked; the scan only says where to look.
- Never compare app-wide totals and call it parity. The unit is the component.
- An extra widget in the port is explained in the ledger or removed.
- A CSS class that exists on both sides but whose rule differs is a gap, and it
  is the easiest one to miss — the class name matches.
- Component parity and test parity are separate claims. Neither implies the
  other, and a port is finished only when both hold.
