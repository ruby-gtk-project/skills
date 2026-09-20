---
name: test-parity
description: Establish and prove test parity between a GNOME app and its Ruby GTK4 port - census the upstream suite test by test, map each one to a named Ruby test, and show the counts match exactly. Use when porting an app to Ruby GTK, when asked whether the tests are ported / how many tests are missing / "do we have test parity", when writing the port's first tests, when reviewing a port PR that adds or changes tests, or before calling any port finished. Also use when a port's suite looks healthy but was never checked against what upstream actually tested.
---

# Test parity

## What test parity means

**A port has test parity when its suite contains exactly one test for every
test in the upstream suite, and nothing is left unaccounted for in either
direction.**

Three claims, all of which must hold:

1. **The counts are equal.** Upstream has N tests; the port has N tests. Not
   "about N", not "N minus the ones that don't apply". N.
2. **The mapping is a bijection.** Every upstream test names exactly one port
   test, and every port test is named by exactly one upstream test. No upstream
   test maps to two port tests; no port test covers three upstream tests at
   once.
3. **Each pair tests the same thing.** The port's test asserts the same
   property, over the same inputs, for the same reason. A test that shares a
   name and asserts something easier is a parity failure wearing a disguise.

Parity is a property of the *census*, not of the number at the bottom of the
test runner. A suite of 34 Ruby tests that were written from scratch has no
parity with a suite of 34 Vala tests; it has a coincidence. Parity exists only
once each pair is written down.

### Why it is defined this way

The upstream suite is the only surviving record of what the original authors
found worth pinning down: the bug that came back, the edge case in the date
parser, the null dereference in #2652. A port that drops a test drops that
knowledge silently and gets a green suite for it. Counting is the cheapest
check that catches it, and the name-by-name census is what makes the count
mean something.

### The one legitimate exception, and how it is handled

Some upstream tests pin language plumbing the port does not have: a Vala
`GObject` construct block, a manual `unref`, a C string-builder. These do not
vanish. They are **substituted**: the ledger row keeps the upstream test, marks
it `substituted`, names the Ruby test that stands in its place, and says in one
line why the direct port is meaningless. The count is preserved — a substituted
test still has exactly one Ruby test opposite it.

There is no `skipped` state, no `n/a` state, and no unticked row that stays
unticked. An upstream test with nothing opposite it is a gap, and a port with
gaps does not have test parity.

## How to establish it

### Step 1 — Census the upstream suite

Work from the upstream branch of the fork (the port's `ruby` branch and the
original share one repo — see `PLAN.md` in `ruby-gtk-project/.github`).

```sh
scripts/test-census.sh <upstream-tree> > upstream-tests.tsv
```

The script finds test cases across the frameworks GNOME apps use — GLib
`Test.add_func` (Vala/C), Python `unittest` / `pytest`, GJS Jasmine `it(...)`,
Rust `#[test]`, Ruby `test_*` / `it`. It emits one row per test:
`file<TAB>identifier<TAB>line`.

**Read the script's output as a lead, not a verdict.** Then open every test
file and write down, for each test, what it actually asserts. The identifier is
rarely enough: `/cli/task_validator/date_format_valid` does not tell you which
formats, or that the empty string is deliberately excluded. That purpose is the
thing you are porting; the name is just its handle.

A test whose purpose you cannot state in a sentence has not been censused.
Do not move on.

### Step 2 — Write the ledger

`TEST_PARITY.md` at the root of the port's `ruby` branch. It is the contract,
and like `PORTING.md` it is the source of truth — not a summary of one.

```markdown
# Test parity — <app>

| | |
|---|---|
| Upstream | `main` @ `<sha>` |
| Port | `ruby` @ `<sha>` |
| Upstream tests | 34 |
| Ported | 34 |
| Gaps | 0 |

## Suite: cli/argument_parser (15 tests)

| # | Upstream test | Purpose | Port test | State |
|---|---|---|---|---|
| 1 | `/cli/argument_parser/add_minimal` | `add` with only `--content` fills the rest from defaults | `test/cli/test_argument_parser.rb#test_add_minimal` | ported |
| 2 | `/cli/argument_parser/unknown_option` | an unrecognised flag is an error, not a silent ignore | `test/cli/test_argument_parser.rb#test_unknown_option` | ported |
| 3 | `/cli/argument_parser/invalid_pin_value` | `--pin` rejects anything but true/false | — | **gap** |
```

One row per upstream test, forever. Rows are never deleted — a ported test that
gets rewritten keeps its row and changes its `Port test` cell. States are
`ported`, `substituted` (with the reason in the Purpose cell) or `gap`.

### Step 3 — Port the gaps

Take gaps in ledger order. For each: read the upstream test, write the Ruby
test that asserts the same property, run it, tick the row.

Name the Ruby test after the upstream one, mechanically, so the mapping is
visible without the ledger:

| Upstream | Ruby |
|---|---|
| `/cli/argument_parser/add_minimal` | `test/cli/test_argument_parser.rb`, `test_add_minimal` |
| `/item-sorting/breaks-a-priority-tie-by-date-added` | `test/core/test_item_sorting.rb`, `test_breaks_a_priority_tie_by_date_added` |

Keep the upstream suite's file structure too. If upstream splits the CLI tests
across three files, the port splits them across three files. A single
`test/all_test.rb` holding 34 tests passes the count and loses the shape.

The port's tests are plain Ruby run under the project `Makefile`'s `test`
target — see the `ruby-gtk-testing` skill for the non-widget checks and the
headless driver. Nothing here asks for a new framework.

### Step 4 — Prove it

```sh
scripts/test-census.sh <port-tree> > port-tests.tsv
wc -l upstream-tests.tsv port-tests.tsv
```

Parity is proven when all four hold:

- the two counts are equal;
- every ledger row has a non-empty `Port test`;
- every test named in the ledger exists, by that name, in the port tree;
- the port's suite passes (`make test`).

Report the numbers, not an adjective. "34/34, suite green" is a claim someone
can re-run. "Good test coverage" is not.

## Worked example — planify-rb

Upstream `main` has four test files and **34** test cases: 26 under `cli`
(`test/cli/test-argument-parser.vala`, `test-task-validator.vala`,
`test-priority-conversion.vala`), 8 under `core`
(`test/core/test-item-sorting.vala`), 1 CalDAV integration test.

The `ruby` branch has `test/test_load.rb`, `test/test_sync.rb` and
`test/drive_main.rb`, and the census counts **173** named `check(...)` cases in
them. They were written for the port; not one of them was written from an
upstream test, and none of the 34 has a counterpart.

So planify-rb's parity ledger opens at **0/34, 34 gaps** — while the port's
suite is five times the size of upstream's. This is the case the skill exists
for. A bigger number is not parity, and a port whose suite is green and
substantial can still have inherited none of the knowledge upstream wrote down.
Those 173 checks are not parity work; they are extra, they stay extra, and they
are listed under `## Extra`. Parity is a floor the port owes upstream, never a
ceiling on what the port may test.

## Rules

- Never lower a test to make it pass. A failing ported test is a port bug found
  — that is the test doing its job.
- Never merge two upstream tests into one Ruby test to save typing. The count
  is the check; collapsing rows disables it.
- Extra Ruby tests with no upstream counterpart are welcome and are listed in
  an `## Extra` section below the tables, outside the count.
- A test that cannot be made to pass is a gap plus an issue, not a comment-out.
- If the upstream app has no tests at all, say exactly that: parity is 0/0, it
  is met trivially, and it means the port has no inherited safety net — which
  belongs in the report, not left as an implication.
