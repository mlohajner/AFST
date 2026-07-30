# AFST — Analytic File Sync Tool

**Sync without the noise. Only what changed, nothing more.**

---

## Philosophy

Most sync tools think file by file: check one, compare, decide, copy, repeat
multiple-thousand times.  
AFST thinks differently.

Instead of walking through directory trees hunting for differences one at a
time, AFST first takes a **snapshot** of the source and destination state.
Then, instead of custom comparison logic, it reaches for a tool that already
does this better than anything else - the standard Unix `diff`. The result is
a fast, clear analysis of what changed, turned directly into a list of files
to transfer.

No magic. Just old, proven tools used in a smarter way.

---

## What makes it different

- **Snapshot, not scanning** -the entire tree is read once, not file by
  file. Scales gracefully even on large directories.
- **`diff` as the decision engine** -instead of hand-written comparison
  logic, it relies on a generic, battle-tested, fast Unix tool.
- **Cumulative and archival** -the sync is intentionally one-directional.
  Nothing gets deleted, nothing gets lost. The destination grows and
  preserves history, it never shrinks to mirror the source.
- **Snapshots as a byproduct** -after every sync, a trace of that moment's
  state remains. Free insight into the past, with no extra code.
- **Simplicity as a feature, not a compromise** -a few dozen lines of
  bash, no dependencies, no configuration, no hidden behavior.

---

## Usage

```
afst.sh SOURCE_DIR DEST_DIR
```

That's it. The tool builds the snapshots, computes the differences, and
transfers only what needs to copy.

---

## GUI

For those who'd rather point and click than type, `afst-gui` wraps AFST in a
minimal [Zenity](https://en.wikipedia.org/wiki/Zenity) front end:  
pick a source folder, pick a destination folder, confirm, and watch it run.
No new logic, no reimplementation — just a thin, honest layer on top of the
same core script.

```
./afst-gui.sh
```

A `.desktop` launcher is included as well, so the GUI can sit right next to
your other applications if you'd rather not touch a terminal at all.

---

## Spirit of the project

AFST doesn't try to be rsync, doesn't try to be Time Machine, doesn't try
to do everything.  
It does one thing: figure out what changed and copy it
and does it in a way that's easy to read, easy to understand, and easy to
trust.

**Sometimes the smartest solution isn't reinventing the wheel, it's pointing
the old wheel in the right direction.**

---

*by Mario Lohajner, 2025* 😃
