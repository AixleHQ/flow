# frozen_string_literal: true

require "aws-sdk-bedrock"

module CloudAuth
  # App-owned seam over bedrock:ListInferenceProfiles — the only truthful answer to "which
  # models can this connection actually invoke".
  #
  # It matters that this is not a static list: an enterprise account exposes its models as
  # **application inference profiles**, whose ARNs are account-specific and are what such a
  # deployment pins. A hardcoded catalogue can never name them.
  #
  # Per docs/testing.md §4 the vendor SDK is never stubbed; tests stub this class and use
  # FakeAwsModelCatalog.
  class AwsModelCatalog
    # A page cap so a very large account cannot turn a model list into a long walk.
    MAX_PAGES = 5
    PAGE_SIZE = 100

    # Each type is asked for EXPLICITLY: ListInferenceProfiles with no typeEquals returns
    # only system-defined profiles, so an account's own application profiles are invisible
    # by default — and those are exactly the ones an enterprise deployment invokes, bills
    # and grants InvokeModel on. Omitting the filter offered a list of models the account
    # was usually not permitted to call.
    TYPES = %w[APPLICATION SYSTEM_DEFINED].freeze

    Profile = Data.define(:id, :arn, :name, :description, :type, :model_arns) do
      # Claude Code accepts a system-defined profile by id, but an application profile only
      # by ARN — the id of an application profile is not a routable model name.
      def model_id = application? ? arn : id
      def application? = type.to_s.casecmp("APPLICATION").zero?
      def anthropic? = model_arns.any? { |a| a.to_s.include?("anthropic") }

      # Claude 3.x carries a 2x "extended access" surcharge on Bedrock and is being retired
      # on a calendar that differs from Anthropic's own, so offering it in a picker is a trap
      # in both money and uptime.
      #
      # The discriminator is where the version sits in the name: legacy models put it before
      # the family (claude-3-sonnet, claude-3-5-sonnet), current ones after
      # (claude-sonnet-4-6, claude-opus-5). Revisit if that convention ever changes again.
      def legacy? = model_reference.match?(/claude-\d/)

      # [major, minor] of the current naming form, for newest-first ordering. Anything
      # unparseable sorts last rather than randomly.
      def generation
        match = model_reference.match(/claude-[a-z]+-(\d+)(?:-(\d+))?/)
        return [ -1, -1 ] if match.nil?

        [ match[1].to_i, match[2].to_i ]
      end

      # An application profile's own name is whatever a team called it, so the underlying
      # model ARN is the only thing that can be classified.
      def model_reference = (model_arns.first || id).to_s

      # A system profile id is "<geo>.<vendor>.<model>": global.anthropic.claude-opus-5,
      # us.anthropic.claude-opus-5. The geography decides price and capacity pool, the rest
      # identifies the same underlying model.
      def geo = id.to_s.split(".").first
      def model_key = id.to_s.split(".", 2).last
    end

    def initialize(region:, access_key_id:, secret_access_key:, session_token:)
      @region = region
      @access_key_id = access_key_id
      @secret_access_key = secret_access_key
      @session_token = session_token
    end

    # @return [Array<Profile>] active profiles only; a profile that is not ACTIVE cannot be
    #   invoked, and offering it would produce a failure at the worst moment.
    def inference_profiles
      collected = []
      failure = nil

      TYPES.each do |type|
        collected.concat(profiles_of_type(type))
      rescue Error => e
        # One type failing is not the same as having no answer: a permission set may grant
        # listing of the account's own application profiles and nothing else, or the
        # reverse. Report only when nothing at all came back.
        Rails.logger.warn("[AwsModelCatalog] could not list #{type} profiles: #{e.message}")
        failure ||= e
      end

      raise failure if collected.empty? && failure

      collected
    end

    private

    def profiles_of_type(type)
      profiles = []
      token = nil

      MAX_PAGES.times do
        resp = client.list_inference_profiles(
          { type_equals: type, max_results: PAGE_SIZE, next_token: token }.compact
        )
        profiles.concat(resp.inference_profile_summaries.filter_map { |s| build(s) })
        token = resp.next_token
        break if token.blank?
      end

      profiles
    rescue ::Aws::Bedrock::Errors::ServiceError => e
      raise translate(e)
    rescue ::Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
      raise Error, "#{e.class.name.demodulize}: #{e.message}"
    end

    def build(summary)
      return nil unless summary.status.to_s.casecmp("ACTIVE").zero?

      Profile.new(
        id: summary.inference_profile_id,
        arn: summary.inference_profile_arn,
        name: summary.inference_profile_name,
        description: summary.description,
        type: summary.type,
        model_arns: Array(summary.models).map(&:model_arn)
      )
    end

    def client
      @client ||= ::Aws::Bedrock::Client.new(
        region: @region,
        credentials: ::Aws::Credentials.new(@access_key_id, @secret_access_key, @session_token),
        retry_limit: 1
      )
    end

    def translate(error)
      # A permission set without bedrock:ListInferenceProfiles is the common case, and it is
      # the user's administrator who has to fix it — so say so rather than looking like a
      # transient failure.
      return DeniedError.new("AccessDenied: #{error.code}") if error.is_a?(::Aws::Bedrock::Errors::AccessDeniedException)

      Error.new("#{error.class.name.demodulize}: #{error.code}")
    end
  end
end
