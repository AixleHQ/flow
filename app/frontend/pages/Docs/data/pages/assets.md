# Assets

**Assets** is the project's file shelf: what people upload for agents to work
from, and what agents produce.

## Folders

Assets defaults to a **folder view** — click a folder to open it, and use the
breadcrumbs at the top to go back up. **New folder** creates one inside
whatever you're currently browsing (or at the top level, from the root).
Folder names can be nested by creating one folder inside another, e.g.
`dashboard` then `specs` inside it.

Every folder's row menu offers:

- **Rename** — renames the folder in place; anything inside it keeps its place.
- **Move** — relocates the folder (and everything inside it) under a different
  folder, or back to the top level.
- **Delete** — only works on an empty folder. A folder that still has files or
  subfolders in it offers **Delete anyway**, which sends everything inside to
  trash along with it.

Prefer one flat list instead? The **All files** toggle next to the folder view
shows every asset with a Folder column, no navigation required. Searching does
the same automatically — a search flattens across every folder so you don't
have to know where a file lives to find it.

> info Company-owned files and folders show up inside a project's Assets (see
> below) but are read-only there — rename, move, and delete only apply to the
> project's own files.

## Uploading

**Upload** takes files from your machine into the project — into whichever
folder you're currently browsing, by default. Anything here can be handed to a
step as an input in the workflow editor's Data Flow section, or attached to a
card so the agent working that card sees it.

## Moving files

Drag a file onto a folder to move it there, or use the file's **Move** action
to pick a destination from the folder tree. To move several files at once,
click **Select** to arm checkboxes, check the files you want, then **Move** or
**Delete** from the bar that replaces the toolbar while selection is active.

## Attaching assets to a workflow

Wherever a workflow, step, or session lets you attach assets, the picker
groups them by folder — pick individual files, or check a folder's header to
pull in everything inside it at once. Folders with nothing in them don't
appear in the picker.

## What agents produce

A run's output starts inside the run. Two ways it reaches the project:

1. **Promote** a file from the run's Assets tab — a deliberate "this one
   matters" gesture.
2. **Review outputs** on the run in the list, keeping what you select.

That two-step shape is on purpose: a long run can touch dozens of files, and
most of them are scratch.

## Finding and versioning

Search narrows the list by name, across every folder. Every asset keeps its
**version history** — open it to see the earlier revisions and where each came
from, which matters when the same report is regenerated weekly by the same
workflow.

> info Assets are per project. Files the whole company should reach live in
> **Company Assets** — see [Company workspace](/docs/company-workspace).
