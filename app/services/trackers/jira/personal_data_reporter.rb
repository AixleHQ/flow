# frozen_string_literal: true

module Trackers
  module Jira
    # Atlassian's Personal Data Reporting API, which every OAuth 2.0 (3LO) app
    # that stores account ids must call: each cycle (7 days unless Atlassian says
    # otherwise in `Cycle-Period`), report the ids kept, and erase the data of
    # those Atlassian answers are closed.
    # https://developer.atlassian.com/cloud/jira/platform/user-privacy-developer-guide/
    #
    # The call needs a 3LO token of the app. Atlassian recommends the app owner's;
    # any active 3LO connection's token is used, the first that works.
    class PersonalDataReporter
      URL = "#{::Jira::AppConfig::API_HOST}/app/report-accounts/".freeze
      BATCH = 90
      MAX_BATCHES = 20
      DEFAULT_CYCLE = 7.days
      CYCLE_KEY = "trackers:jira:personal_data_cycle_seconds"

      def self.cycle
        (Rails.cache.read(CYCLE_KEY) || DEFAULT_CYCLE.to_i).to_i.seconds
      end

      def initialize(logger: Rails.logger)
        @logger = logger
        @counts = { reported: 0, closed: 0, updated: 0 }
      end

      def run
        return @counts.merge(skipped: "no_oauth_app") unless ::Jira::AppConfig.oauth_enabled?

        due = TrackerAccount.for_provider("jira").due(self.class.cycle).order(:id).limit(BATCH * MAX_BATCHES).to_a
        return @counts if due.empty?

        token = reporting_token
        return @counts.merge(skipped: "no_token") unless token

        due.each_slice(BATCH) { |batch| break unless report(batch, token) }
        @counts
      end

      private

      # true to carry on with the next batch.
      def report(batch, token)
        response = http.post(URL, { accounts: batch.map { |a| { accountId: a.account_id, updatedAt: a.last_seen_at.utc.iso8601(3) } } }.to_json,
                             "Authorization" => "Bearer #{token}", "Content-Type" => "application/json", "Accept" => "application/json")
        remember_cycle(response.headers["cycle-period"])

        case response.status
        when 204 then reported!(batch)
        when 200 then act_on(batch, JSON.parse(response.body.to_s).fetch("accounts", []))
        else
          @logger.warn("[Trackers::Jira::PersonalDataReporter] report-accounts answered #{response.status}; retrying next run")
          return false
        end
        true
      rescue Faraday::Error, JSON::ParserError => e
        @logger.warn("[Trackers::Jira::PersonalDataReporter] report-accounts failed: #{e.class}")
        false
      end

      def act_on(batch, accounts)
        accounts.each do |account|
          case account["status"]
          when "closed"
            PersonalDataErasure.erase!(account["accountId"])
            @counts[:closed] += 1
          when "updated"
            @counts[:updated] += 1
          end
        end
        reported!(batch)
      end

      def reported!(batch)
        TrackerAccount.where(id: batch.map(&:id)).update_all(reported_at: Time.current)
        @counts[:reported] += batch.size
      end

      def remember_cycle(header)
        seconds = header.to_s[/\A\d+\z/] && header.to_i
        Rails.cache.write(CYCLE_KEY, seconds.clamp(1.day.to_i, 30.days.to_i)) if seconds
      end

      def reporting_token
        Integration.active.where(provider: "jira").where("settings ->> 'auth_mode' = 'oauth'").order(:id).each do |integration|
          return ::Jira::Credential.new(integration).access_token
        rescue ::Jira::Error, Encryptable::DecryptionError => e
          @logger.info("[Trackers::Jira::PersonalDataReporter] integration #{integration.id} has no usable token: #{e.class}")
        end
        nil
      end

      def http
        Faraday.new do |f|
          f.options.open_timeout = ::Jira::AppConfig.open_timeout
          f.options.timeout = ::Jira::AppConfig.read_timeout
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
