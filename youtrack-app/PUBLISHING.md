# Publishing Aixle Flow to JetBrains Marketplace

Aixle Flow reaches customers only through the public JetBrains Marketplace (vendor: Dualboot
Partners). JetBrains reviews every new app and every new version by hand, usually in 3–4 working
days, and YouTrack never updates an installed app by itself. Plan releases accordingly.

## Before the first upload

1. **Test the build end to end on staging.** Connect from Aixle and from YouTrack, deliver
   created/State/Assignee/comment events, run a tracker trigger and the `tracker_*` tools.
2. **Privacy policy.** The app sends personal data to Aixle (logins, issue ids, who commented
   when), so the listing must link a privacy policy that covers tracker data:
   `https://flow.aixle.com/privacy-policy`.
3. **License.** The repository is Apache-2.0: link `LICENSE` and the source,
   `https://github.com/AixleHQ/flow/tree/develop/youtrack-app`, instead of a developer EULA.
4. **Screenshots** for the listing: the connect page, the consent screen, the setup widget, the
   YouTrack card in Aixle.
5. **Package:** `youtrack-app/bin/package` → `youtrack-app/dist/aixle-flow-<version>.zip`.
   Check `manifest.json`: `name` `aixle-flow` (never change it — it is the app's identity in every
   installed instance), `title` "Aixle Flow" (at most 30 characters), `version`, `vendor`,
   `minYouTrackVersion`, the 40×40 SVG `icon`.

## Vendor profile (once)

1. Sign in at <https://plugins.jetbrains.com> with the JetBrains Account that owns the vendor.
2. Profile menu → **Upload plugin**. The first upload asks to accept the **JetBrains Marketplace
   Developer Agreement** and to create a vendor profile.
3. Profile: type **Organization**, name **Dualboot Partners**, website
   `https://dualbootpartners.com`, a shared support email (it is public).
4. Add the other maintainers to the vendor so a release does not depend on one person.
5. The **Verified vendor** badge is optional and needs a published app first, company documents
   and an email on the company's domain.

## First upload

1. **Upload plugin** → vendor **Dualboot Partners**.
2. **Plugin for: YouTrack**; upload `aixle-flow-<version>.zip`. If Marketplace answers that "the
   plugin root directory must not contain multiple files" and asks for a `.jar` in `lib`, it has
   validated the file as an IntelliJ plugin: the product was not set to YouTrack. A YouTrack app
   keeps its files at the root of the ZIP, as JetBrains' own apps do.
3. **License:** Apache-2.0 (link to `LICENSE`); **Source code:** the `youtrack-app` URL above.
4. **Tags:** integration/automation tags offered by the form.
5. **Channel:** Stable. Do not set **Hidden**: a hidden app is left out of search, and YouTrack
   installs apps from Marketplace search.
6. Submit and wait for the review e-mail.

While the review runs, fill the plugin page: description (English), screenshots, change notes,
links to the privacy policy and support. Once the app is approved, replace the Marketplace search
link in `Youtrack::Config::MARKETPLACE_URL` and in `docs/user-guide/youtrack.md` with the plugin's
own URL.

## New versions

1. Bump `version` in `manifest.json`, run `bin/package`.
2. Plugin page → **Upload update** (reviewed again).
3. Admins update from **Administration → Apps → Aixle Flow → Check for updates**, whenever they
   get to it. Aixle therefore keeps accepting every event payload `version` an installed app may
   still send; a breaking change ships as a new payload version while the old one keeps working.

## Developing

Iterate against a YouTrack instance of our own: upload the ZIP there
(`POST /api/admin/apps/import`, multipart field `file`, admin permanent token) and point the app's
**Aixle Flow URL** at the Aixle you test against. Staging's is
`https://webhooks-staging.flow.aixle.com`, the public host that serves the pairing API. Customers
only ever get the Marketplace build.
