# skills

Agent skills for the GNOME → Ruby GTK4 port campaign (see
[`ruby-gtk-project/.github`](https://github.com/ruby-gtk-project/.github) for
the plan).

`ruby-gtk` and `ruby-gtk-testing` are how the port gets written and run. The
other four are how it gets checked: a port is finished when the Ruby app does
everything the original does, and they define what "everything" means precisely
enough to be checked.

| Skill | Answers |
|---|---|
| [`ruby-gtk`](ruby-gtk/) | How is Ruby GTK4/Libadwaita written here? |
| [`ruby-gtk-testing`](ruby-gtk-testing/) | Does the app actually run and do the thing? |
| [`test-parity`](test-parity/) | Does the port test every single thing upstream tested? |
| [`component-identification`](component-identification/) | What UI does this app actually have? |
| [`component-parity`](component-parity/) | Does the port's UI match the original's? |
| [`accountability-ensurance`](accountability-ensurance/) | Is any of this being excused rather than built? |

`component-identification` produces the inventory; `component-parity` compares
two of them. `test-parity` stands alone. A port is done when test parity and
component parity both hold — neither implies the other.

`accountability-ensurance` guards all three. The parity skills have two states,
`ported` and `gap`, and no third — because the third state is where ports go to
die. It hunts the prose that tries to create one anyway.

## The two definitions everything rests on

**Test parity** — the port's suite contains exactly one test for every upstream
test: equal counts, a bijection between them, and each pair asserting the same
property. Proven by a name-by-name census recorded in `TEST_PARITY.md`, not by
the number at the bottom of the test runner.

**Component parity** — for every component the original builds, the port builds
one that matches on all three axes: same widget type in the same number, same
CSS classes, same signals and actions. Compared per component, never as app-wide
totals. Recorded in `COMPONENT_PARITY.md`.

## Install

Nothing installs these by hand. This repo is the only editable home for all six
skills; everything downstream is a generated copy:

1. A nightly action in
   [`ruby-gtk-project/.github`](https://github.com/ruby-gtk-project/.github)
   syncs `main` here into `port-scaffold/.claude/skills/` there.
2. Every fork's `ruby` branch gets `port-scaffold/` copied onto it.

So: edit a skill here, and it reaches all 76 forks on its own. Editing a copy
in the scaffold or in a fork gets overwritten.

## The scans

Both scripts are grep over source across Vala, C, Python, GJS, Rust, Ruby,
GtkBuilder XML and blueprint. **Look for `.blp`/`.ui` files before running
either** — where they exist they are the component tree, already nested, and
`component-identification` Step 1 says how to read them. They are **leads, not verdicts** — each skill's
"read the files" step is not optional, and both skills document exactly how
their scan over- and under-reports.

```sh
test-parity/scripts/test-census.sh <tree>              # file, test id, line
component-identification/scripts/gir-symbols.sh > scripts/symbols.tsv        # once: the GTK symbol table
component-identification/scripts/component-scan.sh <tree>  # file, kind, value, count
```

Related: `.github/aw/parity-scan.sh` in the hub repo covers the surrounding
literals — actions, accels, GSettings keys, translatable strings, data files.
