# skills

Agent skills for the GNOME → Ruby GTK4 port campaign (see
[`ruby-gtk-project/.github`](https://github.com/ruby-gtk-project/.github) for
the plan).

A port is finished when the Ruby app does everything the original does. These
skills define what "everything" means precisely enough to be checked, and
provide the scans that check it.

| Skill | Answers |
|---|---|
| [`test-parity`](test-parity/) | Does the port test every single thing upstream tested? |
| [`component-identification`](component-identification/) | What UI does this app actually have? |
| [`component-parity`](component-parity/) | Does the port's UI match the original's? |

`component-identification` produces the inventory; `component-parity` compares
two of them. `test-parity` stands alone. A port is done when test parity and
component parity both hold — neither implies the other.

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

The forks vendor skills into `.claude/skills/` on the `ruby` branch:

```sh
git clone https://github.com/ruby-gtk-project/skills /tmp/skills
cp -r /tmp/skills/{test-parity,component-identification,component-parity} \
      .claude/skills/
```

## The scans

Both scripts are grep over source across Vala, C, Python, GJS, Rust, Ruby,
GtkBuilder XML and blueprint. They are **leads, not verdicts** — each skill's
"read the files" step is not optional, and both skills document exactly how
their scan over- and under-reports.

```sh
test-parity/scripts/test-census.sh <tree>              # file, test id, line
component-identification/scripts/component-scan.sh <tree>  # file, kind, value, count
```

Related: `.github/aw/parity-scan.sh` in the hub repo covers the surrounding
literals — actions, accels, GSettings keys, translatable strings, data files.
