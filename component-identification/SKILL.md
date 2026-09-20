---
name: component-identification
description: Enumerate the UI components of a GTK app - every widget, the CSS classes on it, the signals it responds to and the actions it installs - as an inventory another step can compare. Use when porting a GNOME app to Ruby GTK4 and needing to know what UI actually exists, when asked "what widgets does this app have" / "what's in this view" / to list or inventory an app's UI, before planning a port unit, or as the first half of a component-parity check. Works on either side: the original (Vala, C, Python, GJS, Rust, .ui, blueprint) or the Ruby port.
---

# Component identification

## What a component is

**A component is one widget in the app's widget tree, taken together with
everything that makes it that widget rather than a generic one:**

| Facet | What it is | Why it is part of the component |
|---|---|---|
| **Type** | `Adw.ActionRow`, `Gtk.ListBox` | What it is |
| **CSS classes** | `flat`, `suggested-action`, `card` | What it looks like. A `Gtk.Button` and a `Gtk.Button.destructive-action` are not the same control to a user |
| **Signals** | `clicked`, `row-activated`, `notify::selected` | What it does when touched. A button connected to nothing is a decoration |
| **Actions** | `win.new-task` it installs or targets | What command it fires |
| **Owner** | the class/file that builds it | Where it lives in the app |

Identify all five or you have not identified the component. A port that
reproduces the types and drops the CSS classes has produced a grey copy of the
app; one that reproduces types and CSS and drops the signal connections has
produced a screenshot.

**Type alone is not identity.** An app with nine `Gtk.Button`s has nine
components, and telling them apart is the whole job — they differ by their CSS
classes, their signals, and the file they live in.

## The unit the two sides can be joined on: the file

grep cannot reconstruct a widget tree, and a running app's tree cannot be
compared against source. So the inventory is **per file**, with counts.

This roughly matches how both sides are written — the Ruby house style (see the
`ruby-gtk` skill) puts one component class per file with its widgets as
memoized methods — but **do not assume one file is one component.** Upstream
very often splits a single component across two files:

| Upstream | | |
|---|---|---|
| `src/widgets/paginator.rs` | the subclass, the `#[template_child]`s, the callbacks | gtk-rs |
| `data/resources/ui/paginator.ui` | the widget tree, the CSS classes, the signals | GtkBuilder |
| → `lib/app/paginator.rb` | both halves, in the port | Ruby |

The same holds for a `.py` class beside its `.blp`, or a `.vala` class beside
its `.ui`. **The component is the set of files, not the file.** Scan per file,
then union the rows of every upstream file that maps to the same port file
before comparing anything — otherwise the widget tree is on one side of the
join and the callbacks on the other, and both look half-missing.

Multiplicity lives in the counts: three `Adw.ActionRow`s in a file is
`widget  Adw.ActionRow  3`, and a port with two has a gap of one.

## How to identify

### Step 1 — Scan

```sh
scripts/component-scan.sh <tree> > components.tsv
```

One row per distinct item per file:

```
<file>	<kind>	<value>	<count>
core/Widgets/ItemRow.vala	widget	Adw.ActionRow	3
core/Widgets/ItemRow.vala	css	priority-1	1
core/Widgets/ItemRow.vala	signal	row-activated	1
```

`kind` is `widget`, `css`, `signal` or `action`. Paths are relative to the
tree, so two scans diff directly. `Adwaita::ActionRow` (Ruby),
`Adw.ActionRow` (Vala/blueprint) and `class="AdwActionRow"` (GtkBuilder) all
normalise to `Adw.ActionRow`.

### Step 2 — Read the files

The scan is a lead, not a verdict. It matches text, so it over-reports and
under-reports in known ways, and every one of them needs a human decision:

**Over-reports.** Namespaced names that are not widgets at all land in the
`widget` stream: `Adw.Easing`, `Adw.DialogPresentationMode`, `Gtk.Orientation`
— enums, flags and helper types. Strike them; they are not components.
`Gtk.Template`, `Gtk.Template.Child` and `Gtk.Template.Callback` are PyGObject
template plumbing and are filtered by the script, but the widgets they stand
for are real — their types are in the `.blp`/`.ui`, not in the Python.
`Adw.CallbackAnimationTarget` and `Adw.TimedAnimation` are real objects but not
widgets, so they belong under behaviour, not in the widget count.

**Under-reports.** These are the ones that matter, and only reading finds them:

- **Widgets built in a loop.** `foreach (var p in projects) list.append (new ProjectRow (p))` is one scan row and N components on screen. Record it as a *repeater*: one component, variable count, driven by that collection.
- **Widgets built conditionally.** A row added only when a setting is on is a component that exists in a state the scan sees as unconditional.
- **CSS classes set dynamically.** `add_css_class (priority_class ())` attaches a class the scan cannot name. Follow the expression and list every class it can produce.
- **CSS classes from the stylesheet side.** The app's `.css` files define classes the source may apply indirectly. Read them; a class defined and never applied is dead, and a class applied and never defined is a bug worth reporting either way.
- **Composite widgets.** A project's own `ItemRow` is a component whose parts are in another file. The inventory records the use *and* follows into the definition.
- **Bare blueprint declarations.** `ActionRow { }` without its `Adw.` prefix inside a `.blp` is not matched.
- **App-defined template classes.** `<template class="PaginatorWidget" parent="AdwBin">` gives a row for `Adw.Bin` and none for `PaginatorWidget`, because it is this app's own name, not a GTK type. Every `<child>` that instantiates it is a component whose parts are in the file that defines the template — resolve it, and count the uses.
- **Widgets from a shared factory.** A private `build_button` called from three memoized methods is one textual occurrence and three widgets on screen. Count the *call sites*, not the constructor. This is the most common way a correct port reads as a gap of two.
- **Actions whose name is never a literal.** A port that builds `Gio::SimpleAction.new(name)` from a loop over `{'start-tour' => ..., 'next-page' => ...}` installs four actions and puts none of them in the scan, because the prefix (`win.`) is supplied by the widget and the name is a variable. Open every `add_action` / `install_action` / `SimpleAction.new` site and read the names off it. The scan's `action` stream is the least trustworthy of the four for exactly this reason.
- **Signals connected in a loop or a helper.** Same shape as the factory case: one `connect` in a helper called per row is one row in the scan and N live connections.

### Step 3 — Write the inventory

One `## <file>` section per component file, in the order a user meets them
(window, then its pages, then its dialogs — not alphabetical):

```markdown
## core/Widgets/ItemRow.vala — one task row in a list

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ActionRow` | 1 | `item-row`, `priority-{1..4}` (dynamic) | `activated` | priority class recomputed on `notify::priority` |
| `Gtk.CheckButton` | 1 | `circular-check` | `toggled` | completes the task |
| `Gtk.Label` | 2 | `dim-label` (2nd only) | — | content, due date |
| `Gtk.Revealer` | 1 | — | — | holds the detail pane |

Repeaters: none. Conditional: the due-date label only when `item.due != null`.
```

Say what the component *is* in the heading. "one task row in a list" is what
makes the inventory readable a month later; the file path alone is not.

## Scope it

A whole-app inventory of a large GNOME app is thousands of rows and nobody
reads it. Identify components **one unit at a time** — one window, one dialog,
one page, as `PLAN.md` defines a unit — and the inventory stays the size of
the thing being ported.

Absent a `PLAN.md` (see below), take a unit to be **one top-level widget class**
— one `.ui`/`.blp` template, one `impl ObjectSubclass` block, one `GtkWidget`
subclass — together with the source file that backs it and the port file that
corresponds to it. Two additions, without which real parts of the app belong to
no unit at all:

- **One unit for the application class.** `BinaryApplication(Adw.Application)` is not a widget class, but it holds the actions, the accelerators, the About dialog and the preferences entry point.
- **One unit per standalone `.blp`/`.ui` object with no backing source file** — a shortcuts window or a menu definition is a component that no widget subclass owns.

The exception is the opening survey of a fresh fork, where the totals are the
point:

> planify upstream: 1730 widget rows across its source, 144 distinct types, 99
> distinct CSS classes, 195 distinct signals. The `ruby` branch: 325 rows, 81
> types, 33 CSS classes, 29 signals.

That is a map of how much app is left, not an inventory. Do not try to act on
it directly; pick a unit.

## Rules

- Never list a widget type without its CSS classes and signals. A bare type
  list is the inventory that makes a port look finished when it is not.
- Never strike a scan row as "not a widget" without opening the file.
- A dynamic CSS class is listed with every value it can take, not as `dynamic`.
- When a widget's signal handler is the only thing it does, name the handler.
  A component's behaviour is part of its identity.
