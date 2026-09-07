# Secrets & Variables

Values a run needs at the moment it runs: API keys, tokens, endpoints, flags.
They live here instead of in task descriptions and workflow instructions.

## How it works

Add an item, name it, and attach it to the steps that need it. During a run the
agent receives the value through the session's own channel — it never has to
appear in a prompt, and a secret's value is masked in the list.

Search narrows the list by name. Deleting an item goes through the row menu and
asks for confirmation, because a step that expects it will fail without it.

## What belongs here

- Credentials for [connectors](/docs/agent-capabilities) and
  [wrappers](/docs/agent-capabilities)
- Tokens for services a workflow calls
- Configuration that differs between projects — an environment name, a base URL

## What does not

- Your personal agent credential. That is connected in
  [Profile](/docs/getting-started) and belongs to you, not to the project.
- Anything you would not want an agent to be able to read. A step that lists a
  secret can use it.

> warning Pasting a key into a card description or a step's instructions puts
> it in the prompt, the run log, and everyone's screen. Put it here instead —
> that is the whole point of the page.
