require_relative "stubs/github_stubs"
require_relative "stubs/gitlab_stubs"
require_relative "stubs/bitbucket_stubs"
require_relative "stubs/jira_stubs"
require_relative "stubs/confluence_stubs"
require_relative "stubs/temporal_stubs"

module StubSupport
  include GithubStubs
  include GitlabStubs
  include BitbucketStubs
  include JiraStubs
  include ConfluenceStubs
  include TemporalStubs
end
