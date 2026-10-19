# Tracker attachments — technical design

Status: **Built 2026-10-20 on branch `artempartos/tracker-asset-sync-design`, all five providers; the
staging check (§12.2) is still to run.** §15 lists where the build differs from this design. Agreed the same day: the `copy_attachments`
flag (§7.5), applying for Jira's per-tenant quota (§10.1), and delivery straight from the API
documentation to a staging check, with no spike phase (§12), and GitHub files stored as git objects in
the issue's repository (§11).
Extends: [`task-tracker-integrations.md`](./task-tracker-integrations.md), which kept attachments out of
scope (§1). Precedents: files in the Teams design ([`teams-integration.md`](./teams-integration.md) §8.5),
`Slack::FileIngestor`, and the `files` argument of `chat_post_message`.

## 1. Goal and product shape

Every tracker provider (Azure Boards, Jira Cloud, GitHub Projects, Linear, YouTrack) gets file handling
in both directions:

1. **In.** The files on a tracker issue are copied onto the Aixle board task linked to that issue, and
   they land in the agent's workspace. That covers files attached to the issue and files or images
   embedded in its description and comments.
2. **Out.** An agent puts a file onto a tracker issue. The file can be a board-task attachment, a
   project asset, a file in its container, or inline text. It goes onto the issue as an attachment,
   is referenced from a comment, or both.

Both directions use the common `tracker_*` tool set (decision 1 of the tracker design). Three tools are
added. They behave the same for every provider, and the differences between providers stay behind
`Trackers::Provider`.

Out of scope:

- **Mirroring.** A file a person adds to the Aixle card is not pushed to the tracker. A file deleted in
  the tracker is not deleted here. This follows the tracker design's "no mirroring" rule (§1, §6.8).
- **Deleting** tracker attachments.
- **Images embedded in issue descriptions** written by `tracker_create_issue` or `tracker_update_issue`.
  Files go out through attachments and comments only.
- **A `tracker.attachment.*` event** (§8).
- Jira Service Management portal attachments, Jira Data Center, and GitHub Enterprise Server.

## 2. Findings

Short answer to "will this have problems": for **GitHub, yes** — native upload is closed to apps, and
the way around it costs a little; for **Jira, two serious ones**; the other three are routine work.

| Provider | In | Out | Main problem |
|---|---|---|---|
| YouTrack | Native: list, download by signed URL | Native multipart upload; comment attachments | YouTrack Cloud's default size limit is **10 MB** per file (admins can raise it to 500 MB). Attachments restricted to groups. |
| Jira Cloud | Native list (`fields=attachment`); download answers 303 to a media host | Native multipart upload | **The OAuth app shares one 65,000-point hourly quota across all tenants.** Embedding a file inline through the API is unreliable. App-registered webhooks carry no attachment events. |
| Azure Boards | `AttachedFile` relations, plus inline `<img>` in HTML fields and comments | Upload, then link (two calls) | 60 MB per file, 100 per work item. Inline images are not relations. An upload that never gets linked is an orphan. |
| Linear | No file entity: `uploads.linear.app` URLs in markdown, behind an `Authorization` header | `fileUpload` → signed `PUT` → markdown | `Attachment` is a link, not a file. Whether an `actor=app` token works for uploads is unverified. Uploads cannot be deleted. |
| GitHub | No file entity: URLs in markdown. In private repos only a signed-in browser or a 5-minute signed URL from `body_html` reaches them | **Native upload is closed** to any token our App can hold (`ghs_` and `ghu_` both get 404). Files go into the issue's repository as git objects instead, and images render inline in private repos (§11) | People's non-image files (PDF, zip, log) cannot be downloaded by any API token. People's images and video likely can, but that is unverified. |

Details and sources per provider are in §4. §11 covers the way around GitHub's gap.

## 3. What exists

**Two unrelated file systems.**

| | `Asset` + `AssetVersion` | `TaskAsset` |
|---|---|---|
| What | Project and company files, versioned | A board task's attachments, one Shrine file each |
| Origin | `AssetVersion.source`: `upload workflow github session slack teams` | `author_type`: `human agent system`. No source, external id or checksum |
| In the container | `input_asset_ids` are copied to `/workspace/assets/<folder>/<name>` | **Not mounted.** `SessionConfigResolver#board_task_asset_ids` returns `[]` |
| Agent access | `@` references; `read_asset` (text only) | `board_get_task_assets` returns presigned URLs; `board_attach_asset` reads a path in the container |
| Size cap | 1 GB (`AssetFileUploader`) | 1 GB (`TaskAssetUploader`) |

There is no MIME allowlist (files are served from an isolated S3 origin), no checksum and no virus scan.
There is also no shared "bytes to asset" service: each caller builds a `Tempfile` and creates the rows
by hand.

**Inbound precedent.**
- The Slack and Teams ingestors take at most 10 files of 50 MB each. They check the host against an
  allowlist, use folder `slack` / `teams`, and log and skip any failure.
- They run synchronously at fire time, inside `TriggerEngine#fire_workflow`'s `dispatch.with_lock`
  (`input_asset_ids_for`), so downloads happen while the row lock is held.

**Outbound precedent.**
- `chat_post_message` takes a `files` argument. Each entry is resolved by `Concerns::ToolFiles` from
  `content`, `file_path` or `asset_id`.
- For `file_path`, Rails pulls the bytes out of the container with `ContainerRuntime#read_file`, as one
  string with **no size cap**.
- `ContainerRuntime#write_file` exists for the opposite direction.

**Trackers.**
- There are twelve `tracker_*` tools. Writes go through `with_write`, which claims a `tracker_operations`
  ledger row before calling the provider. That code assumes the result is an `Issue` or a `Comment`.
- Every read re-checks scope (`scoped!` / `placed!`).
- `external_resources` links an issue to a task, and `Trackers::TriggerSupport.find_or_create_task`
  resolves the run's task inside the dispatch lock.
- **All five clients speak JSON only.** None does multipart or binary download.
  - YouTrack's client goes through `SafeHttp`, caps responses at 4 MB, and refuses redirects.
  - Jira, GitHub and Linear use Faraday without `SafeHttp`. Jira's client follows no redirect, because
    following one would resend the token.
  - Azure fetches only fixed `dev.azure.com` paths.
- Description and comment formats:
  - Jira uses REST v2, so text is wiki markup.
  - Azure uses HTML.
  - GitHub, Linear and YouTrack use markdown.
  - No converter exists.

**Granted access already covers files**, so no customer re-consent is needed:

| Provider | Existing grant |
|---|---|
| Jira 3LO | `read:jira-work write:jira-work` (`Jira::Oauth::SCOPES`) |
| Linear | `read write` |
| Azure | The service principal is in Contributors, or a narrower group with "Edit work items" |
| YouTrack | The `aixle-flow` service user is a member of each connected project's team |

There are two exceptions:
- **Linear `actor=app`** is unverified (§4.5).
- **GitHub** needs nothing new either. Native upload refuses every token our App can hold (§4.4), so files
  go into the repository through the **Contents: write** the App already has for pushing (§11).

## 4. Provider facts

All of these come from public documentation and community reports, checked on 2026-10-19. Anything
marked *check on staging* is confirmed against a live tenant before its adapter is called done (§12.2). Contract
tests pin an adapter to payloads we wrote ourselves, and the Azure and Bitbucket rounds each found
defects that a green suite had passed.

### 4.1 YouTrack

- **List.** `GET /api/issues/{id}/attachments?fields=id,name,size,mimeType,url,created,author(login),comment(id),removed,draft,visibility(…)`.
  `comment` is null for an issue-level file. Pages use `$top` (default 42). The same `fields` can be
  requested on the issue read we already make.
- **Download.** `url` is relative: `/api/files/<id>?sign=…`. It is fetched with **no** `Authorization`
  header.
  - The signature is bound to the service user, which YouTrack re-checks on every access. It is valid
    for about 3 days.
  - On Server the URL already includes the context path, so join it to the origin, not to the base URL.
- **Upload.** `POST /api/issues/{id}/attachments`, multipart, one field per file.
  - This needs the *Add Attachment* permission. *Check on staging:* confirm the team role grants it.
  - Files can be attached to a comment through `…/comments/{cid}/attachments`. *Check on staging:* this is not
    listed in the current docs. If it fails, upload to the issue and reference the file by name.
- **Embedding.** Markdown `![](name.png)` refers to an attachment **by file name**. Two files with the
  same name make the reference ambiguous.
- **Limits.** Cloud defaults to 10 MB per file and an admin can raise it to 500 MB. Server allows up to
  2 GB. An oversize upload fails at upload time.
- **Visibility.** An attachment can be limited to groups. The service user sees only what its groups
  allow, and an attachment with `visibility` set is restricted (§9.3).
- **Sources:**
  [IssueAttachment](https://www.jetbrains.com/help/youtrack/devportal/api-entity-IssueAttachment.html),
  [download](https://www.jetbrains.com/help/youtrack/devportal/api-usecase-download-issue-attachment.html),
  [attach files](https://www.jetbrains.com/help/youtrack/devportal/api-usecase-attach-files.html),
  [size settings](https://www.jetbrains.com/help/youtrack/cloud/server-configuration-settings.html).

### 4.2 Jira Cloud

- **List.** Add `attachment` to `Jira::Api::ISSUE_FIELDS`. The issue read then returns every file:
  - fields `id filename size mimeType created author`;
  - up to 2,000 per issue, with no paging.
- **Inline images are attachments too.** In REST v2 they appear in wiki markup as `!name.png|…!`, so the
  list covers them. The metadata does not say which comment a file came from.
- **Download.** `GET /rest/api/2/attachment/content/{id}` through `api.atlassian.com/ex/jira/{cloudId}`.
  - The answer is **303** to `api.media.atlassian.com`, with a JWT in the query string valid for about
    10 minutes.
  - The media host ignores `Authorization`, so forwarding the header only leaks the token.
  - A redirect follower that handles only 301 and 302 silently writes zero bytes.
  - `redirect=false` returns the bytes directly from the API host. *Check on staging:* confirm this through the
    gateway for 3LO and for a service account.
  - The body comes back as `application/octet-stream`, so the content type has to come from the
    metadata.
- **Upload.** `POST /rest/api/2/issue/{key}/attachments`.
  - Multipart field `file`, with header `X-Atlassian-Token: no-check`.
  - Up to 60 files per request. A 413 means the file is too large, there are too many files, or the
    issue has reached its cap.
  - Size defaults to 1 GB per file; an admin can set it up to 2 GB.
  - Attachments can be switched off for the whole site. `GET /rest/api/2/attachment/meta` returns
    `enabled` and `uploadLimit`.
  - Uploading the same bytes twice gives two ids.
- **Embedding.** The v3 rich-text media node carries a Media Services id, which is not the attachment
  id. Atlassian's ticket for a mapping is still "Gathering Interest"
  ([JRACLOUD-96384](https://jira.atlassian.com/browse/JRACLOUD-96384)).
  - We use v2, where `!name.png|thumbnail!` embeds an attachment.
  - REST-written wiki images rendered as grey placeholders until a fix in April 2026
    ([JRACLOUD-97685](https://jira.atlassian.com/browse/JRACLOUD-97685)), and a user still reported them
    broken in May 2026. *Check on staging.*
  - The guaranteed fallback is the attachment link `[^name.pdf]`.
- **Author.** A 3LO upload is authored by the person who consented. A service-account upload is authored
  by the service account.
- **Rate limits.** Points-based enforcement has applied to Forge, Connect and **3LO apps** since
  2026-03-02.
  - **Tier 1**, the default, is *one 65,000-point hourly quota shared across all tenants* of the app.
  - **Tier 2** gives each tenant its own pool, but only after an Atlassian review.
  - Writes to one issue are limited to 20 per 2 s and 100 per 30 s.
  - API-token traffic is excluded. The page does not mention service accounts.
- **Events.** `attachment_created` and `attachment_deleted` are **not** delivered to webhooks an app
  registers through REST. `jira:issue_updated` carries a changelog item with field `Attachment`.
- **Sources:**
  [attachments API](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-attachments/),
  [rate limiting](https://developer.atlassian.com/cloud/jira/platform/rate-limiting/),
  [webhooks](https://developer.atlassian.com/cloud/jira/platform/webhooks/),
  [attachment settings](https://support.atlassian.com/jira-cloud-administration/docs/configure-file-attachments/),
  [the 303 redirect, tested](https://leanzero.net/blog/atlassian-attachment-download-redirect).

### 4.3 Azure Boards

- **List.** `AzureDevops::WorkItemService#get` already expands relations, but the tracker's `issue_from`
  drops them.
  - The files are the relations with `rel: "AttachedFile"`: `url` (`…/_apis/wit/attachments/{guid}`),
    plus `attributes.name`, `resourceSize` and `resourceCreatedDate`.
  - There is no MIME type and no author.
- **Embedded images are not relations.** An image pasted into Description, Repro Steps, another HTML
  field or a comment is an uploaded attachment, referenced by `<img src=…/_apis/wit/attachments/{guid}?fileName=…>`.
  Finding them means parsing those fields and the comments.
  - The host is `dev.azure.com/{org}` or the legacy `{org}.visualstudio.com`.
- **Download.** `GET …/_apis/wit/attachments/{guid}?download=true` with the connection's token. There is
  no redirect.
- **Upload** takes two calls:
  1. `POST _apis/wit/attachments?fileName=…` with an octet-stream body returns `{id, url}`.
  2. A JSON Patch `add /relations/-` with `rel: AttachedFile` links it, with `test /rev` as the lock
     (a failed test is 412).
  - An upload that is never linked is an orphan. Nobody can list it, and cleanup needs a preview API
    and a permission we will rarely have. The ledger keeps the uploaded URL, so a retry links that
    upload instead of uploading again (§5.3).
- **Limits** (Services): **60 MB per file and 100 attachments per work item**. An oversize upload is
  refused at upload time.
- **Comments are HTML.** An image is `<img src="{url}">`; any other file is `<a href="{url}">{name}</a>`.
- **Rate limits.** 200 TSTUs per identity per sliding 5 minutes. Each customer organization has its own
  service principal, so the budget is per customer.
- **Sources:**
  [create](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/attachments/create?view=azure-devops-rest-7.1),
  [get](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/attachments/get?view=azure-devops-rest-7.1),
  [limits](https://learn.microsoft.com/en-us/azure/devops/organizations/settings/work/object-limits?view=azure-devops),
  [rate limits](https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rate-limits?view=azure-devops).

### 4.4 GitHub (Projects v2 over the App installation)

**No attachment entity.** A file exists only as a URL in an issue or comment body:
- `github.com/user-attachments/assets/<uuid>` for images and video;
- `github.com/user-attachments/files/<id>/<name>` for other files;
- legacy forms: `user-images.githubusercontent.com` and `github.com/<owner>/<repo>/assets/…`.

**Native upload is closed to us.** GitHub documents no upload API
([community #28219](https://github.com/orgs/community/discussions/28219), open since 2022). GitHub CLI 2.99
(2026-09-01) added `--attach`, which uses an undocumented
`POST uploads.github.com/user-attachments/assets?name=&content_type=&repository_id=`. Three things rule
it out:

- **Our installation token (`ghs_`) gets 404.** The maintainer, 2026-09-02: "This is intended behavior
  for now, but we may re-evaluate in the future based on demand"
  ([cli/cli#14309](https://github.com/cli/cli/issues/14309), open).
- **A user token from our App (`ghu_`) gets 404 too.** The maintainer, 2026-10-14: "currently only first
  party apps like Copilot Cloud Agent can mint tokens that satisfy this API endpoint". No App setting
  changes that ([cli/cli#14495](https://github.com/cli/cli/issues/14495)).
- **Even a PAT gets only nine media types:** png, jpg, jpeg, gif, webp, svg, mp4, mov and webm.
  - A PDF, log, zip or JSON file is refused with 422 "content_type is not included in the list of
    allowed content types" ([report](https://github.com/nemolize/remote-mcp-github/issues/246)).
  - Uploads cannot be deleted.
  - The endpoint does not exist on Enterprise Server.

**There is no upload mutation in GraphQL either.** The public schema has `ReleaseAsset` (read-only) and
`FileAddition` (inside `createCommitOnBranch`), and nothing else.

**A documented path does exist: git objects in the issue's repository.**
- The App already holds **Contents: write**, because sessions push branches (`docs/user-guide/github.md`).
  With it, the Git Database API stores any file as a commit:
  1. `POST git/blobs`
  2. `POST git/trees`
  3. `POST git/commits`, with no parent
  4. `POST git/refs`, under any `refs/<a>/<b>` name ([refs API](https://docs.github.com/en/rest/git/refs#create-a-reference))
- GitHub documents `…/blob/<ref>/<path>?raw=true` for images "in issues, pull requests and comments".
  It says this works "for images in a private repository only if the viewer has at least read access to
  the private repository that contains these images"
  ([formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)).
- `github.com` image URLs are not rewritten to Camo, GitHub's anonymous image proxy, so the browser loads
  them with the viewer's own session. That is why private repositories work.
- The same blob page is a download link for any other file type.
- Other tools already use this pattern:
  [gh-agent-screenshot](https://github.com/mgiovani/gh-agent-screenshot) stores files under
  `refs/uploads/…`.

**Download from a private repo.** The URL needs a signed-in viewer.
- A direct GET with an installation token answers 404
  ([community #148227](https://github.com/orgs/community/discussions/148227)).
- **Images and video have a likely route.** Reading the body as HTML — `Accept:
  application/vnd.github.full+json`, GraphQL `bodyHTML`, or `POST /markdown` with `context` — returns
  `private-user-images.githubusercontent.com/…?jwt=` URLs. These are valid for about 5 minutes and need
  no `Authorization`. Whether this works with a `ghs_` token is *unverified*.
- **Other files (`/user-attachments/files/…`) cannot be downloaded.** GitHub Support: access "is tied to
  a valid browser session", and PATs, OAuth Apps and GitHub Apps are not supported
  ([report](https://codenote.net/ja/posts/github-issue-attachments-download-api-unsupported/),
  [community #162417](https://github.com/orgs/community/discussions/162417)).
- Files we stored ourselves are read back through `GET git/blobs/{sha}`.

**Other facts.**
- In a public repo, every one of these URLs works anonymously.
- Draft issues have no repository; the provider already leaves them out.
- Git limits: GitHub warns at 50 MiB per file and refuses over 100 MiB. Push rulesets (path, extension,
  size) apply to every push, including ours.
- Secondary rate limits: 80 content-creating requests per minute, 500 per hour.

### 4.5 Linear

- **No file entity.** `Attachment` in the GraphQL schema is a **link**: `url`, `title`, `subtitle`,
  upserted by URL and issue. Files are `uploads.linear.app` URLs in the markdown of descriptions and
  comments.
- **Download.** Files are private. Send the same `Authorization` header as for GraphQL.
  - Alternatively, GraphQL returns signed URLs when the request carries
    `public-file-urls-expire-in: <seconds>`.
  - *Check on staging:* whether `uploads.linear.app` accepts the `actor=app` token. One 401 with an API key was
    reported and not reproduced.
- **Upload.**
  1. `fileUpload(contentType, filename, size)` returns `uploadUrl`, `assetUrl` and `headers[]`.
  2. `PUT` the bytes to `uploadUrl` with **every** returned header; a missing one gives 403. `size` must
     match the bytes sent.
  3. Reference `assetUrl` in markdown.
  - Leave `makePublic` false.
  - `attachmentCreate(url: assetUrl)` additionally shows the file in the issue's attachment panel.
  - The size limit is undocumented, and an upload cannot be deleted (`fileUploadDangerouslyDelete` is
    internal).
  - *Check on staging:* that `write` covers `fileUpload` for an `actor=app` token.
- **Rate limits.** An OAuth app gets 5,000 requests and 2M complexity points per hour; an API key gets
  2,500 and 3M.
- **Sources:**
  [upload a file](https://linear.app/developers/how-to-upload-a-file-to-linear),
  [file storage auth](https://linear.app/developers/file-storage-authentication),
  [attachments](https://linear.app/developers/attachments),
  [rate limiting](https://linear.app/developers/rate-limiting).

## 5. Model

### 5.1 Where files land

**In: a copy becomes a `TaskAsset` on the board task linked to the issue.**
- The copy is created with `author_type: system`, the new `source: tracker`, and the run's user as
  `author`.
- **Why `TaskAsset` and not `Asset`:**
  - The card is where people look for an issue's files.
  - The issue-to-task link already exists.
  - A project-asset folder per issue would fill the asset library with ticket files.
- **No linked task.** A run with `subject_policy: none`, or a tool call about an issue no task links to,
  still gets the files in its workspace but keeps no copy. The tool result says so, and
  `tracker_link_task` comes first when a copy is wanted.

**In the workspace.** Task attachments are not mounted into containers (§3), so the download tool
writes each file itself:
- It writes to `/workspace/tracker/<issue key>/<name>` through `ContainerRuntime#write_file` and returns
  the paths.
- A file already copied is written from our copy, with no tracker call.
- When a step session starts on a task, its copied tracker files (`source: tracker`) are written to the
  same paths. That is what makes `copy_attachments` (§7.5) useful to agents.
- Mounting task attachments in general (`task_assets.asset_id`, the TODO in `SessionConfigResolver`) is a
  separate change, which this design neither needs nor blocks.

**Out: any file the agent can name.**
- A `task_asset_id`, from a board task of this project.
- An `asset_id`, for any asset accessible from the project.
- A `file_path` in the container.
- Inline `content`.

This is `chat_post_message`'s `files` shape plus `task_asset_id`, so `Concerns::ToolFiles` gains one
source. The `file_path` source changes to stream into a capped `Tempfile` instead of returning the
whole file as one string (§10).

### 5.2 Tables

```text
task_assets
  + source          varchar NOT NULL DEFAULT 'upload'  -- upload | agent | tracker; backfilled from author_type
  + content_sha256  varchar                            -- set on every new row; NULL on old ones

trigger_bindings
  + copy_attachments boolean NOT NULL DEFAULT false    -- §7.5; only meaningful for the tracker kind

tracker_attachments        -- one row per tracker file a project copied in or put there
  id
  project_id           FK projects ON DELETE CASCADE, NOT NULL
  provider             varchar NOT NULL
  instance             varchar NOT NULL          -- the provider's instance identity (tracker design §5.3)
  issue_id             varchar NOT NULL          -- stable issue id, never the readable key
  external_id          varchar NOT NULL          -- the provider's attachment id; "url:" + digest of the
                                                 -- URL for a file that exists only as an embedded URL
  direction            varchar NOT NULL          -- imported | exported
  content_sha256       varchar NOT NULL
  task_asset_id        FK task_assets ON DELETE SET NULL, NULL     -- our copy on the board task
  tracker_operation_id FK tracker_operations, NULL                 -- exported: the write that made it
  data                 jsonb NOT NULL DEFAULT {} -- name, size, content_type, origin, location
  timestamps
  UNIQUE (project_id, provider, instance, issue_id, external_id)
  INDEX  (project_id, provider, instance, issue_id, content_sha256)
```

Notes:

- **Keyed by project, not by task.** One issue can be linked from tasks in several projects, since two
  Aixle projects may connect the same Jira project. Each project keeps its own copy.
- **`data` never stores a signed URL or an author account id.** Signed URLs are credentials (§9.2).
  Jira account ids are personal data we would have to report to Atlassian's Personal Data Reporting API.
- **`ON DELETE SET NULL` on the copy.** A person deleting the copy from the card does not erase what we
  know about the tracker file. The next download fetches it again.

### 5.3 Identity, dedup and idempotency

- **In.**
  - A row with a copy means the copy is reused and the tracker is not called.
  - Two importers racing (the tool and the copy job, §7.5) meet on the unique index, and the second one
    reuses the first one's copy.
  - A re-upload in the tracker has a new id, so it becomes a new copy. A name clash on the card gets a
    suffix, the way the Slack ingestor does it.
- **Out, per call.** The `tracker_operations` ledger handles it, exactly as for comments. The operation
  is `attach_files`. Its automatic key is digested from the issue, the files' SHA-256 values and the
  comment text, so an agent's identical retry replays the first result.
- **Out, across calls.** If the same project and issue already hold a file with the same SHA-256, in
  either direction, the upload is skipped and the result says `already_on_issue`.
  - Skipping happens only if the tracker still lists that file. The tool lists the issue's files before
    uploading anyway, for the scope check and for limits such as Azure's 100 per work item.
  - `force: true` uploads regardless.
  - This also covers sending an imported file straight back to the issue it came from.
- **Azure's two-step upload.** The ledger row records each uploaded URL before the link call. A retry
  after a failed link links the recorded upload instead of creating another orphan.
  - That needs `TrackerOperation` to keep partial progress in `result`.
  - A timeout stays `unknown`, as today.

## 6. Provider port

### 6.1 Interface

```ruby
module Trackers
  class Provider
    # Attachments. A provider that has none keeps these defaults.
    def attachment_support = AttachmentSupport.none   # list:, download:, upload: (:native | :embedded | :none),
                                                      # markup: (:markdown | :wiki | :html), max_upload_bytes:

    def list_attachments(scope_id, ref)                              = raise NotImplementedError  # -> [Attachment]
    def download_attachment(scope_id, ref, attachment_id, io:, max_bytes:) = raise NotImplementedError  # -> Attachment
    def upload_attachments(scope_id, ref, files)                     = raise NotImplementedError  # [UploadFile] -> [Attachment]
    def attachment_markup(attachment, image:)                        = raise NotImplementedError  # comment snippet
  end
end
```

- **`download_attachment` never takes a URL.**
  - It re-reads the issue, which is the existing scope check.
  - It resolves `attachment_id` against the issue's current files, and streams into `io` up to
    `max_bytes`.
  - An id that is not on that issue is `not_found`.
  - This is what keeps tracker credentials from becoming a fetch-anything primitive (§9.1).
- **`upload_attachments` takes all files at once**, so Jira sends one multipart request (up to 60 files)
  instead of spending its per-issue write budget.
- **`attachment_markup`** returns the snippet a comment uses to show the file, in the tracker's own
  markup.

### 6.2 DTOs

```text
Attachment  id, issue_id, name, size?, content_type?, created_at?,
            origin      (:attached | :embedded)          -- attached file, or a URL in the text only
            location    {kind: description | comment, id?}  -- where an embedded file is referenced
            restricted  bool                             -- visible to fewer people than the issue (§9.3)
            available   bool                             -- false when we know we cannot fetch it
            url?        -- the browser URL; never a signed or credential-bearing URL
UploadFile  io, filename, content_type, size, sha256
```

`Trackers::Issue` gains no attachment field: listing files is a separate call, because three providers
need to parse text or make a second request. The hydrate step (§7.4) asks for files only for the run
context.

### 6.3 Per provider

| | List | Download | Upload | `attachment_markup` (image / other) |
|---|---|---|---|---|
| YouTrack | attachments resource | the signed `url`, no `Authorization` | multipart to the issue; to the comment where it works | `![](name)` / `[name](name)` |
| Jira | `fields=attachment`; `!name!` references mark the location | `content/{id}`: `redirect=false`, or 303 followed to the media host **without** `Authorization` | multipart `file`, `X-Atlassian-Token: no-check`, one request | `!name\|thumbnail!` (*check on staging*) / `[^name]` |
| Azure | `AttachedFile` relations + `<img>` in HTML fields and comments | `attachments/{guid}?download=true` with the token | `POST` octet-stream, then `PATCH` relation with `test /rev` | `<img src>` / `<a href>` |
| Linear | `uploads.linear.app` URLs in description and comment markdown | GET with `Authorization` | `fileUpload` → `PUT` with the returned headers → markdown | `![name](assetUrl)` / `[name](assetUrl)` |
| GitHub | user-attachment URLs in body and comment markdown/HTML, plus our refs (§11.2) | ours: `git/blobs/{sha}`; people's images and video: the signed URL from `body_html`, fetched at once; people's other files `available: false` | git objects on `refs/aixle/attachments/…` (§11.2) | `![name](…/blob/<sha>/<name>?raw=true)` / `[name](…/blob/<sha>/<name>)` |

Each provider needs a binary path next to its JSON client. One shared `Trackers::FileTransfer` provides
it, so the rules in §9 live in one place:
- `SafeHttp`-pinned connections;
- streaming into a capped `Tempfile`;
- a per-provider host allowlist;
- redirects followed only to an allowlisted media host, and never with `Authorization`;
- multipart encoding with RFC 5987 file names.

## 7. Tools

Three tools are added to the twelve, with the same tag (`tracker`), `requires_integration :tracker`,
`inject_when :tracker_run`, target resolution (tracker design §7.2) and error shape.

### 7.1 `tracker_list_attachments` (read)

| Argument | |
|---|---|
| `issue` | id, key or URL |
| `tracker` | optional handle |

- Returns the issue's files: `id`, `name`, `size`, `content_type`, `origin`, `location`, `restricted`,
  `available`, and `task_asset_id` when this project holds a copy.
- Files a person deleted in the tracker are not listed, even when a copy exists.

### 7.2 `tracker_download_attachments` (write, to Aixle only)

| Argument | |
|---|---|
| `issue` | id, key or URL |
| `attachment_ids` | optional; default: every available, unrestricted file, within the caps |
| `tracker` | optional handle |

- Each file is copied onto the linked task (or the copy is reused), and written into the workspace.
- Returns `[{id, name, path, task_asset_id, status}]`, where `status` is `copied`, `reused` or
  `skipped: too_large | restricted | unavailable | over_limit`.
- **Restricted files are never downloaded**, even when named (§9.3).
- **Allowed on `read_only` trackers**, since it writes nothing to the tracker.
- **No ledger row.** `tracker_attachments` and its unique index make it idempotent.

### 7.3 `tracker_attach_files` (write)

| Argument | |
|---|---|
| `issue` | id, key or URL |
| `files` | `[{task_asset_id \| asset_id \| file_path \| content+filename, filename?, image?}]` |
| `comment` | optional text; the files are referenced at its end in the tracker's markup |
| `tracker` | optional handle |
| `force` | upload even when the same bytes are already on the issue |
| `operation_key` | optional idempotency key |

- **Without `comment`,** the files are only attached (YouTrack, Jira, Azure). Providers with no
  attachment list (Linear, GitHub) need a place to put them, so there they post a comment with a
  default text.
- Returns the attachments, `comment_id` when a comment was posted, `operation_key`, and per file one of
  `attached`, `already_on_issue`, `linked` (the GitHub fallback, §11.3) or
  `refused: too_large | count_limit | type_not_allowed | repository_rules`.
- **Refused on `read_only` trackers.**
- **The description warns that a file cannot be taken back.** That holds on GitHub and Linear, and on
  Azure and Jira without permissions we do not ask for. The agent should never send a secret.

`tracker_add_comment` does not gain a `files` argument. A separate tool keeps "attach without
commenting" possible where trackers have real attachments, and leaves the existing tool's contract
alone.

### 7.4 Run context

`shared_context.tracker.issue` gains `attachments`: up to 20 entries of `{id, name, size, content_type,
restricted}`, plus `attachments_total`.

What the extra fields cost per provider at hydrate time:

| Provider | Cost |
|---|---|
| Jira | One more field on the read |
| Azure | The relations already fetched |
| YouTrack | One more `fields` entry |
| Linear and GitHub | Parsing the description already read. Comments are not read at hydrate, so files embedded only in comments show up through `tracker_list_attachments` |

`TrackerContext` adds one line: the issue has N files, and `tracker_download_attachments` puts them in
the workspace.

### 7.5 Copying at fire time: the `copy_attachments` flag

**Agreed 2026-10-19:** a per-binding flag, `trigger_bindings.copy_attachments`, boolean, **off by
default**. It is shown in the tracker trigger form and in the "Connect a board column" drawer, the
one-column intake shortcut.

**What it is for.** Without the flag, files stay in the tracker until an agent asks for them. With it,
every run the binding starts first copies the issue's files onto the Aixle task. That buys three things:

1. **People see the files on the card.** The task is the run's work record. Whoever reviews the run sees
   the screenshots and logs the reporter attached without opening the tracker.
2. **Agents find the files already in their workspace.** Each step session writes the task's copied
   files into `/workspace/tracker/<issue key>/` when it starts. A step needs no tool call, and a step
   whose agent has no tracker tools gets the files too.
3. **The run's inputs outlive the tracker.** The copy stays when someone deletes the file in the
   tracker, or when the tracker is detached, so a re-run or an audit sees what the run saw.

**What it costs.**
- Time and storage for every file, including ones no agent opens.
- On Jira, requests from the app's shared hourly quota (§10).
- Data leaves the tracker: some organizations do not want issue files stored outside it. This is why the
  flag is off unless someone turns it on.

**How it works.**
- After the run is enqueued and its task linked, `Trackers::CopyAttachmentsJob` copies the issue's files
  within the caps (§10).
- It runs **outside** the dispatch lock, unlike the Slack and Teams ingestors, because one issue can
  carry dozens of large files.
- **The first session may start before the job ends.** It gets whatever is copied by then. The context
  says how many files are still missing, and `tracker_download_attachments` fetches them. The tool and
  the job share `Trackers::AttachmentImporter` and the unique index (§5.3), so neither copies a file
  twice.
- Restricted files are never copied (§9.3), and skipped files are listed in the run's context with the
  reason.
- Copies are made on later runs of the same task too. Files already copied are reused, and only new ones
  are fetched.

**Form text** (label, then help):

> **Copy issue files to the task**
> When a run starts, copy the files attached to the issue onto the Aixle task. People see them on the
> card, and every step's agent finds them in its workspace. Leave this off if agents only need some of
> the files — they can fetch those themselves — or if issue files must not be stored outside the
> tracker. Files over 50 MB and files visible only to some people in the tracker are never copied.

**User guide.** The text below goes into `docs/user-guide/trackers.md` in the change that ships the
flag, as a section after "Tracker triggers and delivery":

> ### Files from tracker issues
>
> Agents in a tracker run can read the files on the issue that started it, and can put files onto
> issues.
>
> - **What counts as a file.** Files attached to the issue, and images or files embedded in its
>   description and comments. On Linear and GitHub, files exist only as embedded links, so those are
>   what Aixle finds.
> - **Getting files in.** By default, files stay in the tracker until an agent needs one: it lists
>   them with `tracker_list_attachments` and fetches them with `tracker_download_attachments`. A
>   fetched file is saved on the run's task and placed in the agent's workspace under
>   `/workspace/tracker/<issue key>/`.
> - **Copy issue files to the task.** Turn this on in a tracker trigger, or when connecting a board
>   column, to copy every file of the issue onto the task when a run starts. Use it when the people
>   reviewing runs need the files on the card, when every step should find them in its workspace, or
>   when the run's inputs must stay available after the issue changes. Leave it off when agents only
>   need some files, or when issue files must not be stored outside the tracker.
> - **What is never copied.** Files over 50 MB; more than 20 files or 200 MB per run (the rest stay
>   available to `tracker_download_attachments`); files the tracker shows only to some people — a
>   YouTrack attachment limited to groups, or a Jira file used only in restricted comments.
> - **Putting files on issues.** `tracker_attach_files` attaches a task file, a project asset or a file
>   from the agent's workspace, and can post a comment that shows them.
> - **GitHub.** GitHub lets no app upload attachments the way its editor does. Aixle stores each file
>   in the issue's own repository, under a hidden `refs/aixle/attachments/…` ref that clones and branch
>   lists do not show. The comment shows images inline and links other files, for everyone who can read
>   the repository. Files are limited to 25 MB. A file stored this way cannot be removed from the
>   repository's history, so never send a secret. To keep Aixle from writing to your repositories, set
>   the tracker's file storage to "Link to the Aixle task". PDFs, archives and logs that people attached
>   to a GitHub issue cannot be read through GitHub's API; agents see their names and ask for them.
> - **Limits on the tracker's side.** Azure Boards takes files up to 60 MB and 100 per work item;
>   YouTrack Cloud takes 10 MB per file unless an administrator raised it; Jira takes what the site's
>   attachment settings allow, and refuses files when attachments are turned off.
> - **Deleting.** Deleting a copy on the card does not touch the tracker, and deleting a file in the
>   tracker does not touch the copy.

## 8. Events and loops

**No new event in this design.**
- Jira's app-registered webhooks carry no attachment events.
- GitHub and Linear show a new file only as a body edit.
- A new file is rarely a reason to start work.

A later `tracker.attachment.added` can be derived from:
- Jira's `Attachment` changelog item;
- Azure's `relations.added`;
- the YouTrack app's `issue.attachments.added`.

**Our own uploads cause tracker events.**
- Jira sends `issue_updated` with an `Attachment` item, and Azure sends `workitem.updated`.
- An attachment-only change matches none of the four `tracker.*` events, so it starts nothing.
- A comment posted by `tracker_attach_files` is a `tracker.comment.created` and is attributed through
  the ledger, exactly as for `tracker_add_comment`. For that, `with_write` has to accept the new result
  shape:
  - `result_ref` is the comment id when one was posted;
  - `issue_id` comes from the payload.

**Downloads write nothing to the tracker** and cause no event.

## 9. Security

### 9.1 Tracker credentials are not a fetch primitive

- **No tool argument is a URL.** The agent names an issue and an attachment id. The provider re-reads
  the issue under the existing scope check and finds the file on it.
- **An embedded URL is followed only when:**
  - it appears in that issue's description or comments, as re-read just now; and
  - its host is on the provider's allowlist:

    | Provider | Allowed hosts |
    |---|---|
    | Azure | the connection's organization on `dev.azure.com` or `{org}.visualstudio.com` |
    | Linear | `uploads.linear.app` |
    | GitHub | `github.com/user-attachments`, `private-user-images.githubusercontent.com` |

  Without that rule, a Linear issue in one team could name an upload from another team the app can
  read, and an agent could launder it into the project.
- **Credentials go to the provider's API host only.** Redirects are followed by hand: only to an
  allowlisted media host, only for downloads, and with the `Authorization` header dropped. The cases are
  Jira's media host and GitHub's signed-image host.
- **Every byte transfer runs through `SafeHttp`.** Today the Jira, GitHub and Linear clients do not.

### 9.2 Signed URLs are credentials

The following carry the bearer's access until they expire:
- YouTrack `sign=` URLs (the service user's view, for about 3 days);
- Jira media JWTs;
- GitHub `?jwt=` URLs;
- Linear signed URLs.

They never go into a tool result, a log line, `tracker_attachments.data` or the run context.

### 9.3 Visibility can only narrow, never widen

A copy on an Aixle card is visible to every member of the project. A tracker file that is narrower than
its issue is `restricted`. It is listed without contents and never downloaded:

| Provider | Restricted when |
|---|---|
| YouTrack | `visibility` limits it to groups |
| Jira | Every reference to it is in a comment with `visibility` set |
| Others | — |

A Jira file attached to a restricted comment but not referenced in that comment's text cannot be told
apart through the API. That residue is accepted and documented.

### 9.4 Out is bounded by the project

- An agent can send only:
  - the attachments of tasks on its own project's board;
  - assets accessible from the project;
  - files in its own container.
- `read_only` trackers refuse.
- An agent that can call `tracker_attach_files` can publish project files into the tracker, just as
  `chat_post_message` can into Slack. That is the same trust as the other write tools, and the ledger
  records who did it.
- **GitHub public repositories are public.** A file stored in a public repository (§11.2) is as public as
  the issue it was posted to, which is what GitHub's own attachments do too. Aixle never posts a public
  share link to GitHub.

### 9.5 Untrusted content

- Tracker files are untrusted input: a PDF or image can carry prompt injection, the same as issue text.
- They are stored like any other file: isolated S3 origin, no MIME allowlist.
- File names are cleaned before they become a `TaskAsset` name or a container path: path separators,
  control characters and `..` are dropped, and the length is capped (`SafeRelativePath`).
- Nothing is scanned for malware. No upload path in the app is, and changing that is a platform
  decision beyond trackers.

## 10. Limits and quotas

| Limit | Value | Why |
|---|---|---|
| Download, per file | 50 MB | Parity with the Slack and Teams ingestors; constant |
| Download, per call or copy job | 20 files, 200 MB | Bounds one tool call's time and memory |
| Upload, per file | min(provider limit, 50 MB) | Jira reads `attachment/meta`; Azure 60 MB; YouTrack learns from a 413 (default 10 MB on Cloud) |
| Upload, per call | 10 files | Jira's per-issue write budget; Azure's 100 per work item is checked against the list |

- **Streaming, not strings.** Today `ContainerRuntime#read_file` returns a whole file as one string, in
  the process serving tool calls, and `write_file` takes one.
  - Both gain an IO variant that streams through a `Tempfile` and checks the cap **before** the bytes
    are read.
  - A 1 GB file must never sit in a Ruby string.
- **Jira's shared quota** is handled in §10.1.
- **Azure** budgets are per customer identity, so nothing beyond backoff is needed.
- **GitHub's** limit is 80 content-creating requests per minute, at one comment per `tracker_attach_files`.
  Storing a file (§11.2) costs four further writes, so a call is capped at 10 files there as well.
- **GitHub files are capped at 25 MB** (§11.2), below the general 50 MB.

### 10.1 Jira: one quota for every customer

Our production Jira app is a 3LO app in Atlassian's Tier 1. All its traffic, for every customer, draws on
one pool of 65,000 points an hour. When the pool runs out, every request from every tenant gets 429
until the hour turns. One run copying 20 files spends about 20 points. File traffic is the first feature
that can spend the pool in bulk, so it gets these protections:

1. **No automatic bulk copy by default.** `copy_attachments` is off (§7.5).
2. **Fair share in our own code.** Atlassian gives us one pool, so we divide it ourselves.
   - `Trackers::Jira::Budget` is a per-connection hourly budget kept in Postgres.
   - The interactive tracker tools spend from it and are never refused, unless the whole pool is
     nearly gone.
   - Copy jobs spend only within a connection's share, and wait for the next window when it is used
     up.
   - The shares are constants, tuned from the headers below.
3. **Read the pool's state from every response.**
   - Atlassian reports the pool on every response: `X-RateLimit-Remaining`, `X-RateLimit-NearLimit`,
     and the beta `Beta-RateLimit` / `Beta-RateLimit-Policy`.
   - The Jira client records the latest values per app.
   - Copy jobs pause while `NearLimit` is true.
   - A 429 maps to the existing `RateLimited` error and honours `Retry-After`.
4. **Ask Atlassian for the per-tenant pool (Tier 2).** Agreed 2026-10-19. The process is described
   below.

**Which traffic counts.**
- The rule covers Forge, Connect and 3LO apps, and excludes API-token traffic.
- Connections made with a customer's **service account** authenticate with that account's own OAuth
  credential, not with our app. The documentation does not say which pool they draw on.
- Verification on staging (§12) watches the headers on both connection kinds. If service-account
  connections turn out to have their own limits, the budget treats them separately.

**How Tier 2 is granted.** According to Atlassian's rate-limiting page:
- "Quota increases require a review by Atlassian for Tier 2 Per-Tenant Pool eligibility."
- Asked whether it is available on demand, the page answers: "No, not on demand."
- Requests go through the Partner Portal ("app quota increase requests") or an Atlassian representative.
- The page states no form, review time or eligibility threshold beyond "sustained high or concentrated
  usage".

So the request cannot be a formality: it has to show concentrated per-tenant usage. Before sending it:
- run the headers above in production for a few weeks, so the request carries numbers;
- check whether the Partner Portal accepts a private 3LO app at all. The production "Aixle Flow" app is
  private, because sharing it needs the Personal Data Reporting attestation. If the portal does not
  accept it, the representative route is the only one, and the request goes to Atlassian developer
  support.

**Draft request** (sent by the app owner from the Atlassian developer account that owns the app):

> **Subject:** Per-tenant rate-limit pool (Tier 2) for OAuth 2.0 app "Aixle Flow"
>
> App: "Aixle Flow", OAuth 2.0 (3LO) integration, client id `<prod client id>`, owner
> `<developer account>`.
>
> Aixle Flow runs AI agents on work items in our customers' Jira Cloud sites. Each customer connects
> their own site, and our traffic is per customer by nature: an agent reads a work item, its comments
> and its attachments, transitions it, comments on it and attaches the files it produced. No request
> spans tenants.
>
> In the global pool, one customer's busy hour — for example, a batch of work items whose attachments
> agents need — can exhaust the 65,000-point quota for every other customer at once. We already budget
> per connection on our side, back off on `X-RateLimit-NearLimit` and honour `Retry-After`, and we do not
> poll: events come from dynamic webhooks, and we read only the work items an event or an agent names.
>
> Usage over the last `<N>` weeks: `<peak points/hour overall>` at peak, `<share of the largest tenant>`
> from the largest single tenant, `<number of tenants>` tenants. We are asking for a review for the
> per-tenant pool so that one customer's load cannot block the others.

## 11. GitHub: files in the issue's repository

Link-only GitHub support was rejected on 2026-10-19. A second round of research looked for an API path,
and found one.

### 11.1 Options

| Option | Renders in a private repo | Needs | Verdict |
|---|---|---|---|
| **U1. Git objects on an Aixle ref in the issue's repo**, linked as `blob/<commit sha>/<name>?raw=true` | Images inline for anyone with read access (documented); any other file is a link to its blob page | Contents write, already granted | **Proposed** |
| U2. Native upload with a machine user's PAT, brought by the customer | Yes, natively, including a video player | A machine account per customer org (a paid seat), a PAT that owners approve and someone rotates | Optional later. Undocumented endpoint, media types only, uploads undeletable |
| U3. Release assets | Unknown | Contents write | No: creates tags and `release` events (deploy pipelines listen for those), and immutable releases refuse new assets |
| Native upload with `ghs_` or our App's `ghu_` | — | — | Closed by GitHub (§4.4) |
| A link to the Aixle task | No: a link | Nothing | Kept as the fallback when U1 is refused |
| A public Aixle share link | Through Camo | Nothing | No: anyone with the URL can read the file — the pattern behind the [PixelLeak](https://www.glow.io/blogs/how-ai-agents-exposed-developer-screenshots-from-leading-tech-companies) screenshot exposure |
| Browser-session upload | Yes | A stored session cookie | **Not acceptable**: holding a person's full account |

### 11.2 How U1 works

1. **Store.** One ref per file:
   `refs/aixle/attachments/<issue number>/<first 16 hex of SHA-256>`.
   - The ref points at a parentless commit whose tree holds the file under its cleaned name.
   - The App makes four calls: blob (base64), tree, commit, ref.
   - The same bytes on the same issue give the same ref name. A `422 Reference already exists` means the
     file is already stored and is reused, so retries and races converge without a lock.
   - One ref per file, never a ref that moves. A moved ref would orphan the previous commit, and garbage
     collection would break every URL that pointed at it.
2. **Show.** The comment that `tracker_attach_files` posts references each file by its commit SHA:
   - an image as `![name](https://github.com/<o>/<r>/blob/<commit sha>/<name>?raw=true)`;
   - any other file, including video (GitHub's CSP keeps video from `raw.githubusercontent.com` from
     playing inline), as `[name](https://github.com/<o>/<r>/blob/<commit sha>/<name>)`.
3. **Read back.** `tracker_list_attachments` reports our own files from these refs. Downloading one uses
   `GET git/blobs/{sha}`.

**Why the issue's own repository.**
- Everyone who can read the issue can read its repository, so the file is visible to exactly the issue's
  audience.
- A shared storage repo would need its own access grants and would leak across repos.

**What this does to the repository.**
- **Hidden from everyday git.** Clones fetch `refs/heads/*` and `refs/tags/*` by default, so nobody's
  checkout grows. The branch list and the tag list do not show the ref.
- **Mirrors carry the files.** A `--mirror` clone or a backup tool that copies all refs does. The cap
  below keeps that small.
- **Size cap: 25 MB per file on GitHub.** That is GitHub's own limit for files attached through its
  editor, and half the size at which git starts warning.
- **Rulesets win.** A ruleset refusing the push (file path, extension, size, or "restrict creations") is
  reported to the agent. The file then goes out as a link to the Aixle task instead (§11.3).
- **Our own receiver must ignore these refs.** `/webhooks/github` must ignore `push` and `create` events
  for `refs/aixle/*`, and the session git setup must never fetch them.
- **Workflows.** Whether a push to a ref outside `refs/heads` and `refs/tags` starts GitHub Actions
  `on: push` workflows, or reaches other `push` webhook consumers, is not documented. It is on the staging
  checklist (§12.2). If it does, U1 stays opt-in instead of the default.
- **No deletion.** Deleting the ref does not purge the content: GitHub keeps unreachable objects
  reachable by SHA for a long time, and forks share objects. That is no worse than GitHub's own
  attachments, which cannot be deleted at all. The tool description says so, so that an agent does not
  put a secret in a file it sends.

**Per-tracker setting.** `project_trackers.settings.github_file_storage` is `repository`, the default, or
`aixle_link`.
- A project whose organization forbids apps writing refs, or whose repos are mirrored, switches to links.
- The setting sits on the GitHub tracker's settings page, next to the status field.

### 11.3 The fallback: a link to the Aixle task

The fallback applies when U1 is refused (a ruleset, a repository the installation does not cover, or a
file over 25 MB) or switched off.
- The file is attached to the run's linked task with `source: agent`.
- The comment links the task page, which is login-gated and stable.
- Without a linked task, the call is refused, and the message says so.

### 11.4 In

- **Images and video attached by people** come in through the HTML-rendered body, if the staging check
  passes with `ghs_`.
- **Other files attached by people** (`/user-attachments/files/…`) cannot be fetched by any API token.
  They are listed as `available: false`, with their URL for a person to open. The run's context tells the
  agent so, so it can ask for the file instead of guessing.
- **Files Aixle stored** (§11.2) are always readable.

## 12. Delivery

**Agreed 2026-10-19: no separate spike phase.**
- Each provider is built from its official API documentation. The coding session pulls the current
  reference through context7; the links in §4 are the baseline.
- Each provider is then deployed to staging and checked there in the browser against a real tenant.
- The items marked *check on staging* in §4 make up the staging checklist below. Where staging disagrees with the
  documentation, the adapter changes, and §4 is corrected in the same pull request.

### 12.1 Order

1. **Core, the flag, and the three native providers (YouTrack, Jira, Azure).**
   - Core:
     - `Attachment` and `UploadFile`, the port methods and `Trackers::FileTransfer`;
     - the `task_assets` columns, `tracker_attachments` and `trigger_bindings.copy_attachments`;
     - `AttachmentImporter`, `CopyAttachmentsJob` and the upload path;
     - the three tools;
     - the `task_asset_id` source and streaming in `ToolFiles`;
     - container writes at tool time and at session start;
     - the run-context entries;
     - the flag in the trigger form and the intake drawer;
     - a "from APP-123" badge on the card's attachment list;
     - the user-guide section (§7.5).
   - Jira: `Trackers::Jira::Budget` and recording the rate-limit headers (§10.1).
   - Why these three first: each has real attachments, so the port's native path meets three different
     upload shapes — multipart to the issue, several files in one multipart request, and
     upload-then-link.
2. **Linear.** Embedded files only: parsing and `fileUpload`. Optionally `attachmentCreate`, so the file
   also shows in the issue's panel.
3. **GitHub.** Files out as git objects (§11.2) with the link fallback and the `github_file_storage`
   setting. Files in through the HTML-rendered body.
4. **Later, additive:**
   - a `tracker.attachment.added` event;
   - embedded images in descriptions written by `tracker_create_issue` / `tracker_update_issue`;
   - mounting task attachments into sessions generally.

### 12.2 Staging checklist

Every provider is checked through the same browser walk:
1. Attach files to an issue: an attached file, an image pasted into the description, and one into a
   comment.
2. Move the issue so a binding with `copy_attachments` fires. Check that:
   - the files are on the Aixle card with the "from" badge;
   - the session finds them under `/workspace/tracker/<key>/`;
   - the run's context lists anything skipped.
3. Run a step that calls `tracker_download_attachments` for one file, then `tracker_attach_files` with a
   container file and a comment. Check in the tracker:
   - the file is there;
   - the comment shows it;
   - the comment's echo started no run.
4. Repeat the attach call. Check that it reports `already_on_issue`.
5. Restrict a file in the tracker (where possible). Check that it is listed and never copied.

Per provider, on top of the walk:

| Provider | Also confirm |
|---|---|
| Jira | `redirect=false` through the gateway, otherwise the 303 path; `!name\|thumbnail!` rendering in a REST v2 comment; the rate-limit headers on a 3LO connection *and* a service-account connection |
| YouTrack | `POST …/comments/{id}/attachments` on 2026.x; that the service user's team role may add attachments; the 413 for a file over the Cloud limit |
| Azure | Download of an inline `<img>` with the connection's token; a retry after a failed link reuses the upload. **Staging has no Azure integration**, by design: it does not reuse the production app registration. The check runs on staging with PAT mode switched on for it (`AZURE_DEVOPS_PAT_MODE_ENABLED`), against a test organization |
| Linear | `fileUpload` and the `uploads.linear.app` download with an `actor=app` token *and* with an API key |
| GitHub | That an image stored on `refs/aixle/…` renders in a private repo's comment for a **read-only** member (web and mobile); that the push starts no Actions workflow and see which webhooks it sends; that `full+json`, `bodyHTML` or `POST /markdown` return `?jwt=` image URLs to a `ghs_` token; that `/user-attachments/files/…` links are not signed (so `available: false` is right); a ruleset refusal falling back to the Aixle link |

## 13. Testing

- **Port contract tests.** One per provider, against the app-owned client with recorded payloads,
  following `docs/testing.md`: stub the adapter, never the vendor gem. The payloads are recorded from the
  staging walk (§12.2), not written by hand.
- **`Trackers::FileTransfer` tests** are where §9.1 gets proven:
  - no `Authorization` across hosts;
  - only allowlisted hosts;
  - only URLs present in the issue text;
  - the cap enforced while streaming;
  - 303 followed;
  - zero bytes refused.
- **Importer tests:** the race between the tool and the job, reuse, a copy deleted then fetched again,
  restricted files skipped.
- **Budget tests:** the interactive tools are allowed past a used-up share, jobs wait for the next
  window, and `NearLimit` pauses jobs.
- **The staging walk is the release gate, not CI.** On this integration family, Azure's and Bitbucket's
  rounds each found defects that contract tests had passed: a missing `_links.web`, 412 instead of 409,
  a `302` diffstat.

## 14. Decisions

### 14.1 Agreed 2026-10-19

| # | Question | Decision |
|---|---|---|
| 1 | Copy files automatically when a run starts? | **A per-binding flag, `copy_attachments`, off by default**, with its purpose explained in the form and in the user guide (§7.5) |
| 2 | Jira's shared quota | **Apply for Atlassian's per-tenant pool (Tier 2)**, with usage numbers from the rate-limit headers, and divide the shared pool ourselves until then (§10.1) |
| 3 | GitHub out | Link-only was rejected. **Files go in as git objects in the issue's repository**, and images render inline in private repos (§11) |
| 4 | How it is delivered | **Built from the official API documentation (context7), deployed to staging, checked in the browser.** No spike phase; the staging checklist (§12.2) is the release gate |

### 14.2 Proposed

| # | Question | Proposal |
|---|---|---|
| 5 | Where do inbound files land? | A `TaskAsset` on the linked task, plus the workspace; no copy without a linked task |
| 6 | Tool set | `tracker_list_attachments`, `tracker_download_attachments`, `tracker_attach_files`; `tracker_add_comment` unchanged |
| 7 | Embedding files in comments | Best effort, in the tracker's markup; the guaranteed result is an attachment plus its name |
| 8 | Restricted files | Listed, never downloaded |
| 9 | Dedup out | By SHA-256 per project and issue, checked against the tracker's current list; `force` overrides |
| 10 | GitHub storage default | `repository`, with `aixle_link` per tracker. If the staging check shows a push to `refs/aixle/*` starts workflows, the default flips to `aixle_link` |
| 11 | GitHub native upload through a customer's machine-user PAT (U2) | Not now; revisit if customers ask for a video player or for GitHub's own attachment look |
| 12 | Order | Core + flag + YouTrack, Jira, Azure → Linear → GitHub |

### 14.3 Open

- **Should outbound files also appear on the Aixle card?** That means copying a container file the agent
  sent onto the linked task, so the card shows what was sent. The GitHub fallback (§11.3) needs it; it
  is optional everywhere else. The proposal: the fallback only.
- **Azure on staging.** Staging has no Azure integration by design. The staging walk needs PAT mode
  switched on there against a test organization (§12.2), and that test organization has to exist:
  new Azure DevOps organizations now require an Azure subscription to be linked.

## 15. As built (2026-10-20)

All five providers were built in one change, from the API documentation, ahead of the staging check
(§12.2). Where the build differs from the sections above:

| Area | Design | Built | Why |
|---|---|---|---|
| Port (§6.1) | `upload_attachments(scope_id, ref, files)`, one call for all files | `upload_attachment(scope_id, ref, file)`, one file at a time; `attachments?`, `attachment_list?`, `max_upload_bytes`, `compose_comment` and `attachment_markup` on the port | Each file is recorded in `tracker_attachments` as soon as it lands, so a retry after a failed comment finds it instead of uploading it again (`Trackers::AttachmentExporter`). Jira's per-issue write limit allows the ten files a call can carry |
| File sources (§5.1) | `Concerns::ToolFiles` gains `task_asset_id` and streaming | A separate `Concerns::TrackerFiles` with the four sources, a `stat` size check before a container file is read, and temp files | `chat_post_message`'s contract stays as it is |
| Run context (§7.4) | Up to 20 files listed at hydrate time | The context lists the copies already on the task, read from the database, and what the copy job skipped (`shared_context.tracker.files`); nothing is read from the tracker when a run starts | A listing at fire time would call the tracker inside the dispatch lock, on every event, for files most runs never open |
| Jira budget (§10.1) | Per-connection hourly budget in Postgres | `Trackers::Jira::Budget` in `Rails.cache` (Redis in production): the pool state from `X-RateLimit-*` headers, and 300 downloads per connection per hour for copy jobs; a job that finds the pool near its limit retries in 10 minutes, six times | A counter that resets every hour needs no durability; the agent's own calls are never held back |
| Azure orphan (§5.3) | Partial progress in the ledger row | The upload's answer kept in `Rails.cache` for an hour, keyed by work item and content digest; a retry links it | The ledger row belongs to the whole call, not to one file |
| YouTrack comments (§4.1) | Attach to the comment where it works | Files are attached to the issue and the comment names them | One upload path, the documented one |
| Linear upload (§4.5) | — | The PUT goes to the host `fileUpload` names, through `SafeHttp`, with Linear's headers and never the credential | The signed host is Linear's choice and not documented |
| GitHub storage switch (§11.2) | `settings.github_file_storage` | `project_trackers.settings.file_storage` (`repository` or `aixle_link`), switched by **Link files instead** on the tracker's row | Read by the exporter, not the provider, which serves every tracker of the connection |
| GitHub fallback (§11.3) | Link to the task page | Files over 25 MB, refused by the repository, or with the switch on are attached to the run's task (`source: agent`) and the comment links the board page (`/board?n=<number>`); without a task they are refused with `not_stored` | — |
| Card badge (§12.1) | "from APP-123" | The attachment row's subtitle starts with `from <key>` (`TaskAssetResource#tracker_issue_key`) | — |

Not built: the per-provider `max_upload_bytes` for YouTrack (its limit is learned from the 413), and
GitHub video playback (videos are linked, as §11.2 says).

