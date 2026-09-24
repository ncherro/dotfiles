[← dotfiles](../README.md)

## Notes, code, and the knowledge base

`notes`, `code` and `review` all produce the same shape of thing: a
directory, a tmux session, and a Claude transcript. They are joined by a
metadata file — `.session.json` in a notes dir, `.review-meta.json` in a review
dir, `.notes-link` at a worktree root — which is what lets `wip`, `notes-gc` and
`recall` answer questions across all three without keeping a separate list.

`bin/notes-index` is the only thing that reads all of it. Everything else shells
out to it. Some of what it does is non-obvious:

- **The knowledge base is the routing table.** Topic slugs, frontmatter
  `aliases`, `index.md` hooks and `**Scratch:**` pointers are what `notes`
  matches against, which is why `notes playcount` can find a dir whose name
  shares no words with the query.
- **Dirs that predate `.session.json` still work.** Topics are inferred from the
  KB's own `**Scratch:**` lines, so nothing needed migrating.
- **`**Scratch:**` is parsed as a block, not a file-wide grep.** A topic that
  merely *mentions* another topic's scratch dir must not claim it.
- **A Claude transcript dir is named after the path it was opened at**
  (`-Users-you-workspace--notes-<slug>`, with `/`, `_` and `.` all mapped to
  `-`). It does not follow a dir that moves. That is why `notes-merge` records
  it as provenance, and why `recall` keys on the `cwd` field inside the
  transcript rather than trying to decode the dir name — the encoding is lossy
  and cannot be reversed.

Two gotchas worth not rediscovering:

- **fzf matches the line as transformed by `--with-nth`.** A trailing hidden
  field is invisible to the matcher, so anything searchable has to be in the
  visible columns. That is why aliases are a column in the picker.
- **`local` in zsh prints the variable** when it re-declares one that already
  exists in the same scope. Declare once, above the loop.

The helpers are dry-run or read-only by default. `notes-merge` in particular
refuses to move a dir with a live tmux session, and writes an undo script with
byte-for-byte backups to `$NOTES_DIR/.merge-undo/<timestamp>/`.

The matching slash commands (`/wrap`, `/code`, `/notes-merge`, `/kb-tidy`,
`/review-pr`) live in a separate, work-specific repo and are not part of these
dotfiles. The workflow they add up to is written up in `$NOTES_DIR/README.md`.
