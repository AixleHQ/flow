# Copilot CLI: sign-in with a Microsoft Entra work account — research

**Date:** 2026-11-11. **CLI:** `@github/copilot` 1.0.108, the version `copilot_cli` pins
(`docs/design/copilot-cli-runtime.md`).
**Question:** can a customer connect the `copilot_cli` runtime with a Microsoft Entra work
account, as the CLI's own `/login` offers on a Mac ("Your organization (Microsoft Entra)"),
rather than with a GitHub account?
**Verdict:** not today. The CLI does not offer that sign-in inside a Linux container, and
none of the paths that would get around it is documented or testable without an Entra
tenant licensed for Copilot. GitHub accounts that sign in *through* Entra already work.
§5 lists what would change that.

Nothing here was run against an Entra account: there is none to test with. The facts below
come from the CLI itself (help, its JavaScript bundle and the strings of its native
runtime), the SDK's published types as quoted in github/copilot-sdk#2882, and runs of the
CLI in the `aixle/copilot-cli` image.

## 1. Three things called "Entra"

| Case | Who | Status in Aixle |
| --- | --- | --- |
| **A. A GitHub account whose sign-in goes through Entra** (SAML SSO, or Enterprise Managed Users on github.com) | Most enterprise Copilot Business/Enterprise customers | **Works.** `copilot login --device-code` sends the user to github.com, which hands the sign-in to their Entra tenant in their own browser. The token we store is an ordinary `gho_`. |
| **B. EMU on GitHub Enterprise Cloud with data residency** (`<tenant>.ghe.com`) | Customers whose GitHub lives on a GHE.com host | **Not offered.** The CLI supports it (`copilot login --device-code --host https://<tenant>.ghe.com`; the adapter already reads a `proxima` login and pins `COPILOT_GH_HOST`), but the auth terminal runs the github.com login only. |
| **C. A Microsoft Entra work account with no GitHub account** — the Mac's "Your organization (Microsoft Entra)" | Customers who buy Copilot through Microsoft | **Not possible today** (§2–§4). |

The rest of this document is case C, which is what was asked for.

## 2. What the CLI does with an Entra account

The CLI knows several account kinds; its own labels are `githubDotCom` ("GitHub"),
`proxima` ("GitHub Enterprise Cloud"), `entraEmu` ("GitHub"), `entra` ("Microsoft
Entra") and `loki` ("Microsoft 365"). The SDK's types, as quoted in github/copilot-sdk#2882,
describe two of them:

- `entra`: "Microsoft Entra sign-in that derives a GitHub (EMU) credential". The Entra
  sign-in is a way to *reach* a managed GitHub account, not a replacement for one. The SDK
  needs an Entra application `clientId` for it, and "the runtime does not supply a default
  application". The CLI's TUI uses the VS Code registration
  (`aebc6443-996d-45c2-90f0-388ff96faa56`).
- `loki`: "A Microsoft 365 Copilot (Loki) inference account", which runs models through
  Microsoft 365 Copilot instead of GitHub (§4).

## 3. Why the Entra option is missing in the container

- **It is gated in the native runtime, not by anything we configure.** `/login` lists the
  providers the runtime reports as available, and it hides `entra` in the container. The
  decision is in the runtime (`entra_auth_is_enabled`, plus a platform check: "Selected
  Entra account is unsupported on this platform"). Measured on 1.0.108, the option stays
  hidden with `DISPLAY` or `BROWSER` set, signed in or not, and with `--experimental`.
  `copilot_cli_entra_access_disabled` exists as a server-side switch that turns it *off*.
- **The sign-in needs something a container does not have.** On macOS and Windows it goes
  through the OS broker (OneAuth, the CLI's default since 1.0.10x). Without a broker it
  falls back to a browser authorisation-code flow whose redirect lands on the CLI's
  `127.0.0.1` port, inside the container, where the user's browser cannot reach.
- **The only override is a debug hook.** `COPILOT_DEBUG_ENTRA_BROKER_URL` points the CLI at
  an external broker. It is undocumented, carries no compatibility promise, and the CLI
  ships about three releases a week; a product built on it would break without notice.
  There is also `COPILOT_ENTRA_ONEAUTH=0`, which only disables the broker.

## 4. The Microsoft 365 Copilot path (`loki`)

The runtime has a Microsoft 365 Copilot inference client: endpoints
`https://loki.delve.office.com/api/v1/llmapi` (and `msit.`/`df.` variants), and the
variables `COPILOT_LOKI_TOKEN`, `COPILOT_LOKI_TOKEN_COMMAND`, `COPILOT_LOKI_RESOURCE` and
`COPILOT_LOKI_BASE_URL`, read by an external-token provider (`loki_external`).

On paper that is the headless route: a token command that prints an Entra access token for
the Loki resource, much as `COPILOT_PROVIDER_API_KEY_COMMAND` works for BYOK. It is not
usable today:

- None of it is documented, and github/copilot-sdk#2882 (opened 2026-10-29), which asks
  exactly whether a Microsoft 365 Copilot licence can be used this way and with which
  Entra application, has no answer.
- The token is for a Microsoft service resource (the default of `COPILOT_LOKI_RESOURCE` is
  not visible in the strings). Whether a third-party multi-tenant Entra app can be granted
  that permission at all, or whether it is reserved for Microsoft's first-party apps, is
  unknown.
- Usage would be billed and metered by Microsoft, not as GitHub AI credits, so the OTLP
  `github.copilot.nano_aiu` pricing would not apply and session cost would need its own
  source.

## 5. What it would take, and what to do now

**Recommendation:** do not build case C yet. Keep case A as the answer for enterprise
customers, add case B when a customer on GHE.com asks, and track GitHub for case C.

| Step | Unblocks | Effort |
| --- | --- | --- |
| Ask GitHub to support Entra sign-in in a headless Linux CLI, ideally by device code (Entra supports it), and to document the Loki variables: comment on github/copilot-sdk#2882 or open an issue on github/copilot-cli | C | none on our side |
| An Entra test tenant with a Copilot licence (Microsoft 365 Copilot for `loki`, or an EMU enterprise for `entra`) | testing any of C | procurement |
| Case B: offer the `--host` login (a host field before the auth terminal, or the CLI's `/login` menu), and test it on a GHE.com tenant | B | ~1 day + a GHE.com tenant |
| Once GitHub supports C: capture the Entra login like other runtimes (or our own device-code flow feeding `COPILOT_LOKI_TOKEN_COMMAND`), add refresh — Entra access tokens last about an hour, so this is a `refresh: :server` credential — and a cost source for Microsoft-billed usage | C | ~1 week, after the above |

## Sources

- `copilot login --help`, `copilot help environment`, `copilot help config` (1.0.108)
- The CLI's `cli-main.js` and its native `runtime.node` (strings), in `aixle/copilot-cli`
- github/copilot-sdk#2882, "Can the SDK use an existing Microsoft 365 Copilot subscription via Entra sign-in, without registering an Entra app?"
- https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli
- `docs/design/copilot-cli-runtime.md` §0.1, "Microsoft Entra sign-in (not built)"
