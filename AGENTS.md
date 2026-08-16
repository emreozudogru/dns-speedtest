# Agent instructions

This repository is maintained by automated coding agents as well as humans.

## Git: smallest commit, then push

The owner wants to **see every tiny change** in git history. Nothing is
too small to commit: one TSV flag flip, one comment, one README sentence,
a typo fix, a single function.

After **every** such change:

1. Stage **only** the files that belong to that single change.
2. Create a commit immediately. Keep the diff as small as possible. Do not
   batch unrelated edits into one commit.
3. `git push` the current branch to `origin` after that commit, unless the
   network is unavailable. Do not wait for the user to ask.

Do not accumulate a pile of uncommitted work. Do not wait until the end of
the task to commit. One logical change = one commit = one push.

If a task needs several steps (for example: add a resolver, then document
it), commit and push after each step.
