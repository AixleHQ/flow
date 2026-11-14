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
    # How long after a refresh token is spent presenting it again may still be
    # a retry of that refresh, whose response was lost (rotate!). The runner's
    # retries come about 1, 3, 7, 15 and 31 s after the first failure.
    RETRY_WINDOW = 60.seconds

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
    # `created_by` is the user who asked for it; the machine that spends the
    # token is recorded as added by them (Registration.register!).
    def mint_registration!(runner, created_by: nil)
      raise ArgumentError, "registration tokens are minted for manual runners only" unless runner.manual?

      token = generate(:registration)
      RunnerCredential.transaction do
        live = lock_live_runner!(runner.id)
        RunnerCredential.create!(runner: live, kind: :registration, token_digest: RunnerCredential.digest(token),
                                 expires_at: REGISTRATION_TTL.from_now, created_by: created_by)
      end
      token
    end

    def issue_pair!(environment, family_id: SecureRandom.uuid, rotated_from: nil)
      access = generate(:access)
      refresh = generate(:refresh)
      now = Time.current
      common = { runner_id: environment.runner_id, company_id: environment.company_id,
                 runner_environment_id: environment.id, family_id: family_id, rotated_from_id: rotated_from&.id }
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

    # Spends a refresh token on a new pair of the same family, which names it
    # as `rotated_from`. A refresh token presented a second time means two
    # holders have it, so the whole family is revoked and the machine moves to
    # `failed`, held by no session, with the reason in `state_reason` for people
    # (§9.2, Runners::Machines.fail!); the revocation commits before the
    # refusal is raised.
    # A spent token counts as reused even past its own expiry: the 30-day limit
    # is for a token left unused, and the family it was rotated into may still
    # be live.
    #
    # The one exception is a retry after a lost response (retry?): within
    # RETRY_WINDOW of the spend, while the pair it issued is unused, the
    # gateway revokes that pair and issues a fresh one, as a rotation does. The
    # window counts from the first spend, so a retry does not extend it.
    #
    # Locks in the one order every issuer and revoker uses: the runner (see
    # lock_live_runner!), then the environment (Registration.unregister! locks
    # it to mark it `gone`), then the credential, then the pair it issued. So
    # a pair is never issued into a revoked runner or a `gone` environment.
    def rotate!(credential)
      reused = false
      pair = RunnerCredential.transaction do
        lock_live_runner!(credential.runner_id)
        environment = RunnerEnvironment.lock.find(credential.runner_environment_id)
        credential.lock!
        if credential.revoked? || environment.gone?
          nil
        elsif credential.used?
          issued = RunnerCredential.unrevoked.where(rotated_from_id: credential.id).lock.to_a
          if retry?(credential, issued)
            revoke!(issued)
            Rails.logger.info("[Runners::Credentials] refresh retried within the window: " \
                              "environment #{environment.id}, family #{credential.family_id}")
            issue_pair!(environment, family_id: credential.family_id, rotated_from: credential)
          else
            reused = true
            revoke_family!(credential.family_id)
            Runners::Machines.fail!(environment, REUSE_DETECTED)
            nil
          end
        elsif credential.expired?
          nil
        else
          credential.update!(used_at: Time.current)
          issue_pair!(environment, family_id: credential.family_id, rotated_from: credential)
        end
      end
      raise Refused.new("credential_reuse_detected", "This refresh token was already used; the machine's credentials are revoked.") if reused
      raise Refused.new("invalid_token", "The refresh token is revoked or expired.") if pair.nil?

      pair
    end

    # A spent refresh token presented again is the runner retrying a refresh
    # whose response it never got when it was spent less than RETRY_WINDOW ago
    # and the pair the spend issued (`issued`, its unrevoked credentials) is
    # whole and unused: the gateway has accepted neither its access token
    # (record_use!) nor its refresh token. Anything else is reuse.
    def retry?(credential, issued)
      ok = credential.used_at > RETRY_WINDOW.ago && issued.none?(&:used?)
      ok && issued.map(&:kind).map(&:to_s).sort == %w[access refresh]
    end

    # Records an access token's first accepted use, which ends the retry
    # window of the refresh that issued it (retry?). One write per token: a
    # token already marked is not written again.
    #
    # Returns false when the token was revoked before its use was recorded,
    # and the request must then be refused. The update sets `used_at` only on
    # an unrevoked row and takes that row's lock, which rotate! also takes
    # when it reads the issued pair, so the two are serialized: if a retry
    # revokes the pair first, the update changes no row; if the use commits
    # first, rotate! sees it and treats the spent token as reuse. A row that a
    # concurrent request of the same token marked first is still accepted.
    def record_use!(credential)
      return true if credential.used?

      now = Time.current
      recorded = RunnerCredential.where(id: credential.id, used_at: nil, revoked_at: nil)
                                 .update_all(used_at: now, updated_at: now) == 1
      return RunnerCredential.unrevoked.where(id: credential.id).where.not(used_at: nil).exists? unless recorded

      credential.used_at = now
      true
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

    def revoke!(credentials)
      now = Time.current
      RunnerCredential.where(id: credentials.map(&:id)).update_all(revoked_at: now, updated_at: now)
    end

    def generate(kind)
      "#{PREFIXES.fetch(kind)}#{SecureRandom.urlsafe_base64(32)}"
    end
  end
end
