# Third-Party Licenses

Aixle Flow is distributed under the [Apache License 2.0](LICENSE). It
incorporates and depends on third-party software, each governed by its own
license. This file provides the attribution required by those licenses.

- **Scope:** all third-party components bundled with or distributed as part of
  the application, plus the runtime stack shipped in the container image.
- **Snapshot date:** 2026-06-15. Versions reflect `Gemfile.lock`,
  `package.json` / `yarn.lock`, and the `Dockerfile` / `docker-compose.yml` as
  of that date.
- **Build-time and development-only tooling** (linters, test frameworks, build
  tools) is listed separately and is **not** distributed with the application.
- This file is a curated attribution snapshot. See
  [Regenerating this file](#regenerating-this-file) for how to refresh the
  complete machine-readable list before each release.

All licenses below are compatible with redistribution under Apache 2.0. No
component is licensed under a copyleft license that propagates to the application
(no GPL-only, SSPL, BUSL, or Commons Clause code is distributed). Components
under weak-copyleft licenses
(MPL-2.0, LGPL-2.1+) are used unmodified via dynamic loading/linking — see
[`NOTICES.md`](NOTICES.md) for the specific obligations.

---

## 1. Runtime stack (shipped in the container image)

| Component | Version | License |
|---|---|---|
| Ruby | 3.4.2 | Ruby License / BSD-2-Clause |
| Ruby on Rails | 8.1.x | MIT |
| PostgreSQL (client lib `libpq`) | 15.3 | PostgreSQL License |
| Redis | 7.2 | BSD-3-Clause |
| OpenSSL | 3.x | Apache-2.0 |
| libvips | (Alpine `vips`) | LGPL-2.1+ — see [`NOTICES.md`](NOTICES.md) |
| Alpine Linux (musl, distro tooling) | 3.21 | MIT |
| busybox | (Alpine) | GPL-2.0-only (OS boundary; does not propagate) |
| Linux kernel | (host/Alpine) | GPL-2.0-only (syscall boundary; does not propagate) |
| Temporal server / UI | 1.29.0 / 2.43.3 | MIT |
| Traefik | v3.6.6 | MIT |

> The Linux kernel and busybox are GPL-2.0-only but sit at the OS boundary
> (syscall interface); their license does not extend to application code running
> on top of them. Temporal and Traefik run as separate service processes.

## 2. Ruby gems — production (distributed)

| Gem | Version | License |
|---|---|---|
| aasm | 5.5.0 | MIT |
| actionmcp | 0.104.1 | MIT |
| administrate | 0.19.0 | MIT |
| administrate-field-jsonb | 0.4.7 | MIT |
| administrate-field-shrine | 0.0.5 | MIT |
| alba | 3.10.0 | MIT |
| audited | 5.8.0 | MIT |
| aws-sdk-s3 | 1.186.0 | Apache-2.0 |
| bcrypt | 3.1.20 | MIT |
| bootsnap | 1.18.4 | MIT |
| config | 5.5.2 | MIT |
| csv | 3.3.2 | Ruby / BSD-2-Clause |
| docker-api | 2.4.0 | MIT |
| enumerize | 2.8.1 | MIT |
| faraday-retry | 2.3.1 | MIT |
| gitlab | 5.1.0 | BSD-2-Clause |
| haml-rails | 2.1.0 | MIT |
| hashie | 5.0.0 | MIT |
| image_processing | 1.14.0 | MIT |
| inertia_cable | 0.2.2 | MIT |
| inertia_rails | 3.19.0 | MIT |
| jwt | 2.10.1 | MIT |
| kramdown | 2.5.1 | MIT |
| kramdown-parser-gfm | 1.1.0 | MIT |
| kubeclient | 4.13.0 | MIT |
| lograge | 0.14.0 | MIT |
| minitar | 0.12.1 | Ruby / BSD-2-Clause |
| oas_rails | 0.14.0 | MIT |
| octokit | 10.0.0 | MIT |
| oj | 3.16.10 | MIT |
| omniauth | 2.1.3 | MIT |
| omniauth-google-oauth2 | 1.2.1 | MIT |
| omniauth-oauth2 | 1.8.0 | MIT |
| omniauth-rails_csrf_protection | 1.0.2 | MIT |
| pagy | 9.3.4 | MIT |
| pg | 1.5.9 | BSD-2-Clause |
| puma | 6.6.0 | BSD-3-Clause |
| pundit | 2.5.0 | MIT |
| rack-cors | 2.0.2 | MIT |
| rails | 8.1.2 | MIT |
| rails-i18n | 8.0.1 | MIT |
| ransack | 4.3.0 | MIT |
| redis | 5.4.0 | MIT |
| responders | 3.1.1 | MIT |
| rolify | 6.0.1 | MIT |
| rotp | 6.3.0 | MIT |
| ruby-filemagic | 0.7.3 | Ruby License |
| rubyzip | 2.4.1 | BSD-2-Clause |
| sentry-rails | 6.4.1 | MIT |
| sentry-ruby | 6.4.1 | MIT |
| shrine | 3.6.0 | MIT |
| solid_mcp | 0.5.0 | MIT |
| stackprof | 0.2.28 | MIT |
| temporalio | 1.0.0 | MIT |
| thruster | 0.1.13 | MIT |
| ts_routes | 1.0.3 | Apache-2.0 |
| typelizer | 0.12.0 | MIT |
| virtus | 2.0.0 | MIT |
| vite_rails | 3.0.19 | MIT |
| websocket-client-simple | 0.9.0 | MIT |

### Notable transitive gems

| Gem | Version | License | Note |
|---|---|---|---|
| aws-sdk-core / aws-sigv4 / aws-eventstream / aws-partitions / aws-sdk-kms | (various) | Apache-2.0 | via aws-sdk-s3 |
| ffi | 1.17.2 | BSD-3-Clause | |
| google-protobuf | 4.33.0 | BSD-3-Clause | |
| msgpack | 1.8.0 | Apache-2.0 | |
| nokogiri | 1.19.0 | MIT | bundles libxml2/libxslt (MIT) |
| sorbet-runtime | 0.5.x | Apache-2.0 | |
| domain_name | 0.6.x | BSD-2-Clause / BSD-3-Clause / MPL-2.0 | weak copyleft — see [`NOTICES.md`](NOTICES.md) |
| llhttp-ffi | 0.5.1 | MPL-2.0 | weak copyleft — see [`NOTICES.md`](NOTICES.md) |
| event_emitter | 0.2.6 | MIT | see [`NOTICES.md`](NOTICES.md) |

All other transitive gems are MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, or
Ruby-licensed.

## 3. JavaScript / TypeScript — production (bundled into client)

| Package | Version | License |
|---|---|---|
| @dnd-kit/core | 6.3.1 | MIT |
| @dnd-kit/sortable | 10.0.0 | MIT |
| @dnd-kit/utilities | 3.2.2 | MIT |
| @emoji-mart/data | 1.2.1 | MIT |
| @emoji-mart/react | 1.1.1 | MIT |
| @inertia-cable/react | 0.2.2 | MIT |
| @inertiajs/react | 3.0.2 | MIT |
| @inertiajs/vite | 3.0.2 | MIT |
| @mantine/core, dates, form, hooks, modals, notifications | 9.0.0 | MIT |
| @rails/actioncable | 8.1.300 | MIT |
| @sentry/react | 10.47.0 | MIT |
| @tabler/icons-react | 3.41.1 | MIT |
| @tanstack/react-table | 8.21.3 | MIT |
| @uiw/react-codemirror (+ extensions/themes) | 4.25.9 | MIT |
| @uppy/aws-s3 | 5.1.0 | MIT |
| @uppy/core | 5.2.0 | MIT |
| @uppy/utils | 6.2.2 | MIT |
| @xterm/xterm (+ addon-fit, addon-web-links) | 6.0.0 | MIT |
| date-fns | 4.1.0 | MIT |
| dayjs | 1.11.20 | MIT |
| emoji-mart | 5.6.0 | MIT |
| lodash | 4.17.21 | MIT |
| mantine-form-zod-resolver | 1.3.0 | MIT |
| mermaid | 11.14.0 | MIT |
| nanoid | 5.1.5 | MIT |
| nuqs | 2.8.9 | MIT |
| react | 19.x | MIT |
| react-dom | 19.x | MIT |
| react-markdown | 10.1.0 | MIT |
| react-resizable-panels | 4.9.0 | MIT |
| react-syntax-highlighter | 15.6.6 | MIT |
| react-zoom-pan-pinch | 3.7.0 | MIT |
| recharts | 3.8.1 | MIT |
| remark-extract-toc | 1.1.0 | MIT |
| remark-gfm | 4.0.1 | MIT |
| use-debounce | 10.1.1 | MIT |
| zod | 3.25.76 | MIT |
| zustand | 5.0.12 | MIT |

### Notable transitive npm packages

| Package | License | Note |
|---|---|---|
| @codemirror/*, @lezer/* | MIT | |
| @bufbuild/protobuf | Apache-2.0 AND BSD-3-Clause | |
| cytoscape, d3 | MIT / ISC | via mermaid / recharts |
| dompurify | MPL-2.0 OR Apache-2.0 | Apache-2.0 selected |

All other transitive npm packages are MIT, Apache-2.0, ISC, or BSD-licensed.

---

## 4. Development / build-time only (NOT distributed)

These are used to develop, test, lint, and build the application. They are not
present in the production container image or the client bundle, so their
licenses impose no obligation on the distributed work. Listed for completeness.

**Ruby (dev/test):** brakeman (Brakeman Public Use License — non-OSI, dev-only,
see [`NOTICES.md`](NOTICES.md)), rubocop + plugins (MIT), foreman (MIT),
spring (MIT), bullet (MIT), byebug (BSD-2-Clause), debug (Ruby / BSD-2-Clause),
pry / pry-byebug / pry-rails (MIT), dotenv / dotenv-rails (MIT),
factory_bot(_rails) (MIT), faker (MIT), letter_opener(_web) (MIT),
capybara (MIT), minitest + extensions (MIT / BSD-2-Clause), mocha (MIT /
BSD-2-Clause), simplecov (MIT), webmock (MIT).

**JavaScript (dev):** typescript (Apache-2.0), vite (MIT), vitest (MIT),
eslint + plugins (MIT), prettier + plugins (MIT), sass-embedded (MIT),
typescript-eslint (MIT), @types/* (MIT). Build tool `lightningcss` (MPL-2.0,
transitive via vite) runs at build time only and is not bundled — see
[`NOTICES.md`](NOTICES.md).

**Package managers:** Yarn 4 (BSD-2-Clause), Bundler (MIT).

---

## Regenerating this file

This snapshot was produced from authoritative registry data (rubygems.org,
registry.npmjs.org, GitHub License API) verified against the lockfiles. To
regenerate a complete, machine-checked attribution list before a release:

```sh
# Ruby — full gem license report
bundle install
gem install license_finder
license_finder report --format=markdown

# JavaScript — full npm license report
yarn install
yarn dlx license-checker-rseidelsohn --markdown --production
```

Run these in CI and reconcile any new or changed licenses against
[`NOTICES.md`](NOTICES.md) before publishing a release.

---

*This file is provided for attribution and does not constitute legal advice.*
