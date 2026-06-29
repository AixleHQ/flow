# Notices

This product, **Aixle Flow**, includes third-party software. A full attribution
list is in [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md). This file
records the specific notices and obligations that require explicit documentation
under the licenses of certain components.

All components below are compatible with redistribution as part of Aixle Flow,
which is licensed under the [Apache License 2.0](LICENSE). None of them imposes
a copyleft obligation on Aixle Flow's own source code.

---

## Weak-copyleft components (MPL-2.0 / LGPL-2.1+)

The following components are licensed under weak (file- or library-level)
copyleft. Their obligations apply to **those components**, not to Aixle Flow's
own code, **provided they are used unmodified via dynamic loading/linking** — as
they are here. If any of them is modified, the modified source of that component
must be made available under its original license.

| Component | Ecosystem | License | How it is used |
|---|---|---|---|
| **libvips** | System library (Alpine `vips`, `vips-dev`, `vips-tools`) | LGPL-2.1+ | Dynamically linked shared library, installed via Alpine `apk`. Used by the `ruby-vips` / `image_processing` gems. No libvips source is copied into or statically compiled into the application. |
| **llhttp-ffi** | Ruby gem (transitive, via `http`) | MPL-2.0 | Loaded dynamically via Ruby `require`. No source files copied into the application. |
| **domain_name** | Ruby gem (transitive, via `http-cookie` → `http`) | BSD-2-Clause / BSD-3-Clause / MPL-2.0 | The MPL-2.0 portions are separate files, loaded dynamically via `require`. No source files copied into the application. |
| **lightningcss** | npm (transitive, via `vite`) | MPL-2.0 | Build-time only. Invoked during the Vite build; its source is not included in the distributed JavaScript bundle. |

**Obligation:** for MPL-2.0 and LGPL-2.1+ components, the corresponding source
is available from the upstream projects, and recipients may obtain, modify, and
relink them. These components are redistributed unmodified.

---

## Components with confirmed/clarified licenses

| Component | Note |
|---|---|
| **event_emitter** (gem 0.2.6, transitive via `websocket-client-simple`) | rubygems.org lists no license field. The upstream repository (`shokai/event_emitter`) is published under the **MIT License**, confirmed via the GitHub License API. Treated as MIT. |

---

## Development-only component with a non-OSI license

| Component | License | Note |
|---|---|---|
| **brakeman** | Brakeman Public Use License (non-OSI) | Security scanner in the `:development` Gemfile group only. **Not distributed** with the application. Anyone running it must comply with the [Brakeman Public Use License](https://brakemanscanner.org/brakeman_public_use_license.html); commercial use beyond the free terms requires a Brakeman commercial license. |

---

## Operational pin: Redis

Aixle Flow pins **Redis 7.2** (`redis:7.2-alpine`), which is licensed under
**BSD-3-Clause**. Redis 7.4 and later are released under RSAL v2 / SSPL, which
are **not** OSI-approved open-source licenses and are incompatible with
redistribution as part of an Apache-2.0-licensed product. The Redis version must stay
pinned at 7.2.x; any upgrade requires either a Redis commercial license or
migration to **Valkey** (BSD-3-Clause, a Linux Foundation fork). This pin is
enforced in `docker-compose.yml` and `docker-compose.ci.yml`.

---

*This file is provided for attribution and notice purposes and does not
constitute legal advice.*
