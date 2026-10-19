# frozen_string_literal: true

module Gitlab
  # What a group Owner's one-time OAuth token is spent on
  # (docs/design/gitlab-tracker.md §4): the groups they own, then a service
  # account in the one they pick — a Maintainer there, holding an `api` token —
  # which the connection runs as from then on. The person's token is not kept.
  class ServiceAccountSetup
    NAME = "Aixle Flow"
    MAINTAINER = 40
    OWNER = 50

    Result = Data.define(:service_account, :token)

    def initialize(rest)
      @rest = rest
    end

    def person
      raw = @rest.get("/user")
      { id: raw["id"].to_s, username: raw["username"], name: raw["name"] }
    end

    # [{ id:, full_path:, name: }] — the groups the person owns, where they may create one.
    def owned_groups
      @rest.paginate("/groups", { min_access_level: OWNER, order_by: "path" }, limit: 200).map do |g|
        { id: g["id"].to_s, full_path: g["full_path"], name: g["full_name"].presence || g["name"] }
      end
    end

    def create!(group_id)
      group = ERB::Util.url_encode(group_id.to_s)
      account = @rest.post("/groups/#{group}/service_accounts",
                           { name: NAME, username: "aixle-flow-#{SecureRandom.hex(4)}" })
      member!(group, account["id"])
      token = @rest.post("/groups/#{group}/service_accounts/#{account['id'].to_i}/personal_access_tokens",
                         { name: NAME, scopes: %w[api] })
      Result.new(service_account: { id: account["id"].to_s, username: account["username"], name: account["name"] },
                 token: { id: token["id"].to_s, token: token["token"], expires_at: token["expires_at"] })
    end

    private

    # A group's service account may already be its member.
    def member!(group, user_id)
      @rest.post("/groups/#{group}/members", { user_id: user_id, access_level: MAINTAINER })
    rescue Trackers::Error::Conflict
      nil
    end
  end
end
