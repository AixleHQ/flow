# Rotating a user-connection OAuth client

GitHub, GitLab and Bitbucket let each person connect their own account through the
deployment's one OAuth client (`GITHUB_APP_CLIENT_ID`, `GITLAB_OAUTH_CLIENT_ID`,
`BITBUCKET_OAUTH_CLIENT_ID`, with `GITLAB_ENDPOINT` for the GitLab host).

**Changing the client id, or `GITLAB_ENDPOINT`, makes everyone reconnect.** Only credentials made
with the client the deployment is configured with now count. After the change:

- a person's old connection is not shown, not handed to agents by the `*_user_token` tools and
  not used by the pull-request tools that act as them: they read as not connected;
- the old credentials are not refreshed, and lapse;
- people connect again from Profile → Connected accounts. A reconnect makes a new credential
  with the new client; their consents for projects are kept until they disconnect;
- *Disconnect* deletes every credential of the person for the provider, old client included. At
  the provider it revokes only the current client's grant. Grants made with the old client stay
  listed in the person's account there until they remove them, or the old client is deleted.

Steps:

1. Create the new client at the provider and set its id and secret in the deployment's settings.
2. Deploy. Tell people to reconnect.
3. Delete the old client at the provider, which ends its grants.

A connect whose identity lookup fails stores nothing, so a reconnect that fails leaves the person's
previous connection as it was.
