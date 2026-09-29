# Team & Access

Membership has two levels, and they answer different questions: *who belongs to
the company* and *who works on this project*.

## Roles

| Role | Can |
| --- | --- |
| **Admin** | Everything an employee can, plus members, integrations, settings, and the company-wide analytics, sessions, and assets |
| **Employee** | Work inside the projects they are on: cards, workflows, runs, resources |
| **Viewer** | Read. Boards, runs and results are visible; nothing is started or changed |

A role is per company. Being a viewer in one workspace and an employee in
another is normal, and onboarding adapts: a viewer is never asked to connect an
agent.

## Getting people in

There are two ways, and only one of them works out of the box.

**By invitation.** An admin invites an address from **Members → Invite**. The
person gets a link, accepts, and joins with the role they were given. This always
works, needs nothing set up, and is the only way in until the step below is done.

**By email domain.** Anyone signing in with an address at the workspace's domain
joins without an invitation — useful once a team is more than a handful of people.
It is switched on with **Accept new people automatically** on Settings → Access,
and it does nothing until the domain is **verified**.

### Verifying your domain

Creating a workspace proves that somebody receives mail at one address. Letting
everyone from the domain in is a claim on the whole domain, so it waits for a
record only the domain's owner can publish:

```
Name:   _aixle-challenge.yourcompany.com
Value:  aixle-domain-verification=<the token shown on Settings → Access>
```

Publish it in your DNS, then press **Check now**. DNS usually takes a few minutes
to spread, so "we could not find that record yet" means *not yet* rather than
*wrong*.

Until it is verified, nothing else about the workspace changes — invitations work
exactly as before, and the automatic-joining switch simply has no effect.

> info Verifying decides who gets **in**, not who owns the domain: a domain
> already taken by another workspace cannot be claimed again either way.

## Company members

**Members** under the company lists everyone in the workspace, searchable by
name. An admin can promote an employee to admin from the row menu.

## Project members

A project's **Members** page controls who is on this project. **Add
Collaborator** opens a picker listing only company users who are not already
here, so you cannot add someone twice. The project owner is badged and cannot
be removed; removing anyone else asks first.

Members are matched by name *and* email when you search, which is the quicker
route in a company where several people share a first name.

> info Adding someone to a project does not give them a credential. They still
> connect their own agent in [Profile](/docs/getting-started) before they can
> run anything.
