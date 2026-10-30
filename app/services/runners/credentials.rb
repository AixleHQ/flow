# frozen_string_literal: true

module Runners
  # Issues, checks and rotates the tokens of the runner gateway
  # (docs/design/agent-runtimes/DESIGN.md §9.2). A token is returned once, by the
  # call that issues it; only its SHA-256 digest is stored (RunnerCredential).
  #
  #   token = Runners::Credentials.mint_registration!(runner)    # "Add machine" (task 12) calls this
  #   pair  = Runners::Credentials.issue_pair!(environment)      # on register
  #   pair  = Runners::Credentials.rotate!(refresh_credential)   # POST /runner/v1/token
  module Credentials
    REGISTRATION_TTL = 1.hour
    ACCESS_TTL = 1.hour
    # A refresh token is used once, so this is also how long one may go unused.
    REFRESH_TTL = 30.days

    PREFIXES = { registration: "arreg_", access: "aracc_", refresh: "arref_" }.freeze

    REUSE_DETECTED = "credential reuse detected"

    # The access token is what the runner sends on every call; the refresh
    # token is sent only to POST /runner/v1/token.
    Pair = Data.define(:access_token, :access_token_expires_at, :refresh_token, :refresh_token_expires_at)

    class Refused < StandardError
      attr_reader :reason

      def initialize(reason, message)
        @reason = reason
        super(message)
      end
    end

    module_function

    # A single-use token that registers one machine of a `manual` runner within
    # an hour. There is no endpoint for it yet: tests and local development call
    # this, and "Add machine" will (§15 task 12).
    def mint_registration!(runner)
      raise ArgumentError, "registration tokens are minted for manual runners only" unless runner.manual?

      token = generate(:registration)
      RunnerCredential.create!(runner: runner, kind: :registration, token_digest: RunnerCredential.digest(token),
                               expires_at: REGISTRATION_TTL.from_now)
      token
    end

    def issue_pair!(environment, family_id: SecureRandom.uuid)
      access = generate(:access)
      refresh = generate(:refresh)
      now = Time.current
      common = { runner_id: environment.runner_id, company_id: environment.company_id,
                 runner_environment_id: environment.id, family_id: family_id }
      RunnerCredential.create!(common.merge(kind: :access, token_digest: RunnerCredential.digest(access),
                                            expires_at: now + ACCESS_TTL))
      RunnerCredential.create!(common.merge(kind: :refresh, token_digest: RunnerCredential.digest(refresh),
                                            expires_at: now + REFRESH_TTL))
      Pair.new(access_token: access, access_token_expires_at: now + ACCESS_TTL,
               refresh_token: refresh, refresh_token_expires_at: now + REFRESH_TTL)
    end

    # The credential `token` names if it may be used now: not revoked, not
    # expired and, for a single-use registration token, not used.
    def usable(token, kind:)
      credential = RunnerCredential.find_by_token(token, kind: kind)
      return nil if credential.nil? || credential.revoked? || credential.expired?
      return nil if credential.registration? && credential.used?

      credential
    end

    # Spends a refresh token on a new pair of the same family. A refresh token
    # presented a second time means two holders have it, so the whole family is
    # revoked and the environment records why (§9.2); the revocation commits
    # before the refusal is raised.
    def rotate!(credential)
      reused = false
      pair = credential.with_lock do
        if credential.revoked? || credential.expired?
          nil
        elsif credential.used?
          reused = true
          revoke_family!(credential.family_id)
          credential.runner_environment.update!(state_reason: REUSE_DETECTED)
          nil
        else
          credential.update!(used_at: Time.current)
          issue_pair!(credential.runner_environment, family_id: credential.family_id)
        end
      end
      raise Refused.new("credential_reuse_detected", "This refresh token was already used; the machine's credentials are revoked.") if reused
      raise Refused.new("invalid_token", "The refresh token is revoked or expired.") if pair.nil?

      pair
    end

    def revoke_family!(family_id)
      now = Time.current
      RunnerCredential.unrevoked.where(family_id: family_id).update_all(revoked_at: now, updated_at: now)
    end

    def generate(kind)
      "#{PREFIXES.fetch(kind)}#{SecureRandom.urlsafe_base64(32)}"
    end
  end
end
