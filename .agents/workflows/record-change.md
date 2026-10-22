# /record-change

Record a finished change, after its build and tests have passed.

1. Add an entry to `Docs/Thesis/FORK_CHANGES.md`: a row in section 2's summary table and a
   subsection with why, what changed, files, and verification (the commands run and their result
   lines). List anything left unverified under "Open items".
2. Add one bullet to the 5.7 section of `CHANGELOG.md` with its area tag, for example
   `**[Ingestion]**`, and an evidence note.
3. Show the owner the diff of both files. Commit only if the owner asks, adding files by name.
