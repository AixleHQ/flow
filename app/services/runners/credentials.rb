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
    # this, and "Add machine" will (§15 task 12). Like every issuer, it locks
    # the runner first (lock_live_runner!), so a revoked or deleted runner gets
    # no token and a revocation running alongside revokes the one minted here.
    def mint_registration!(runner)
      raise ArgumentError, "registration tokens are minted for manual runners only" unless runner.manual?

      token = generate(:registration)
      RunnerCredential.transaction do
        live = lock_live_runner!(runner.id)
        RunnerCredential.create!(runner: live, kind: :registration, token_digest: RunnerCredential.digest(token),
                                 expires_at: REGISTRATION_TTL.from_now)
      end
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
    # expired, not of a `gone` environment (§9.2) and, for a single-use
    # registration token, not used.
    def usable(token, kind:)
      credential = RunnerCredential.find_by_token(token, kind: kind)
      return nil if credential.nil? || credential.revoked? || credential.expired?
      return nil if credential.registration? && credential.used?
      return nil if credential.runner_environment&.gone?

      credential
    end

    # The refresh credential `token` names if it may be presented to rotate!:
    # not revoked, not of a `gone` environment, and either unexpired or spent.
    # A spent one passes, even past its own expiry, so that rotate! can detect
    # its reuse (§9.2). Anything else is refused before the runner or the flag
    # is checked (§6.2).
    def refreshable(token)
      credential = RunnerCredential.find_by_token(token, kind: :refresh)
      return nil if credential.nil? || credential.revoked?
      return nil if credential.expired? && !credential.used?
      return nil if credential.runner_environment&.gone?

      credential
    end

    # Spends a refresh token on a new pair of the same family. A refresh token
    # presented a second time means two holders have it, so the whole family is
    # revoked and the environment records why (§9.2); the revocation commits
    # before the refusal is raised. A spent token counts as reused even past
    # its own expiry: the 30-day limit is for a token left unused, and the
    # family it was rotated into may still be live.
    #
    # Locks in the one order every issuer and revoker uses: the runner (see
    # lock_live_runner!), then the environment (Registration.unregister! locks
    # it to mark it `gone`), then the credential. So a pair is never issued
    # into a revoked runner or a `gone` environment.
    def rotate!(credential)
      reused = false
      pair = RunnerCredential.transaction do
        lock_live_runner!(credential.runner_id)
        environment = RunnerEnvironment.lock.find(credential.runner_environment_id)
        credential.lock!
        if credential.revoked? || environment.gone?
          nil
        elsif credential.used?
          reused = true
          revoke_family!(credential.family_id)
          environment.update!(state_reason: REUSE_DETECTED)
          nil
        elsif credential.expired?
          nil
        else
          credential.update!(used_at: Time.current)
          issue_pair!(environment, family_id: credential.family_id)
        end
      end
      raise Refused.new("credential_reuse_detected", "This refresh token was already used; the machine's credentials are revoked.") if reused
      raise Refused.new("invalid_token", "The refresh token is revoked or expired.") if pair.nil?

      pair
    end

    # Holds the runner's row against a revocation until the caller's
    # transaction ends, and refuses a runner that is already revoked or
    # deleted. Revoking updates that row before it revokes the runner's
    # credentials in the same transaction (Runner#revoke_credentials), so an
    # issuer that takes this lock first has its pair revoked with the rest, and
    # one that takes it after sees the runner revoked (§9.3). FOR SHARE lets
    # issuers of one runner run side by side; only the revocation waits.
    def lock_live_runner!(runner_id)
      runner = Runner.lock("FOR SHARE").find(runner_id)
      raise Refused.new("runner_revoked", "The runner is revoked or deleted.") if runner.revoked? || runner.deleted?

      runner
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
