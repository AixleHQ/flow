# frozen_string_literal: true

require "aws-sdk-ssooidc"
require "aws-sdk-sso"

module CloudAuth
  # App-owned seam over the two AWS IAM Identity Center APIs the device flow needs:
  # SSO OIDC (register a client, run the device grant, refresh) and the SSO portal
  # (enumerate accounts/roles, mint role credentials).
  #
  # Per docs/testing.md §4 the vendor SDK is never stubbed — tests stub THIS class and
  # use FakeAwsSsoClient. Vendor exceptions are translated so callers only ever see
  # CloudAuth errors.
  #
  # Why the flow runs here rather than inside the agent container:
  # agent containers are ephemeral and cannot show a browser, and a credential source
  # inside one cannot talk to the user at all (its stderr is discarded). Doing it
  # server-side also means we hold the client registration, so refresh-token
  # portability between machines never becomes a question. See
  # docs/research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md.
  class AwsSsoClient
    # Required, or CreateToken returns no refresh token and the connection dies with
    # the first access token.
    SCOPES = %w[sso:account:access].freeze

    # Identity Center caps client registrations at 90 days. Refresh hard-stops at that
    # boundary, so a connection must be re-authorised before then no matter how long
    # the org's portal session is.
    REGISTRATION_MAX_AGE = 90.days

    # Both portal listings are paginated, and an organisation whose users are assigned to
    # more accounts than one page holds is the normal case, not the edge: reading only the
    # first page hides accounts the user was actually granted, with no error to notice.
    # `max_result` is deliberately not sent — the SDK model carries no range for it, so a
    # value we cannot verify against a real instance risks a validation failure on the one
    # call the whole connect depends on. The service's own page size applies instead.
    MAX_PAGES = 20

    Registration = Data.define(:client_id, :client_secret, :expires_at)
    DeviceAuthorization = Data.define(
      :device_code, :user_code, :verification_uri, :verification_uri_complete, :interval, :expires_in
    )
    Token = Data.define(:access_token, :refresh_token, :expires_at)
    Account = Data.define(:account_id, :account_name, :email)
    RoleCredentials = Data.define(:access_key_id, :secret_access_key, :session_token, :expiration)

    def initialize(region:)
      raise ArgumentError, "region is required" if region.blank?

      @region = region
    end

    # The start URL doubles as the issuer URL: there is no separate sso_issuer_url
    # concept, the CLI forwards whatever is configured as the start URL.
    def register_client(client_name:)
      resp = oidc.register_client(client_name: client_name, client_type: "public", scopes: SCOPES)
      Registration.new(
        client_id: resp.client_id,
        client_secret: resp.client_secret,
        expires_at: Time.zone.at(resp.client_secret_expires_at.to_i)
      )
    rescue ::Aws::SSOOIDC::Errors::ServiceError, ::Seahorse::Client::NetworkingError => e
      raise translate(e)
    end

    # `verification_uri_complete` must be handed to the user verbatim. It is NOT
    # constructible: the documented device.sso.<region>.amazonaws.com host does not
    # resolve, and real instances return per-instance portal hosts.
    def start_device_authorization(registration:, start_url:)
      resp = oidc.start_device_authorization(
        client_id: registration.client_id,
        client_secret: registration.client_secret,
        start_url: start_url
      )
      DeviceAuthorization.new(
        device_code: resp.device_code,
        user_code: resp.user_code,
        verification_uri: resp.verification_uri,
        verification_uri_complete: resp.verification_uri_complete,
        interval: resp.interval.to_i.clamp(1, 60),
        expires_in: resp.expires_in.to_i
      )
    rescue ::Aws::SSOOIDC::Errors::ServiceError, ::Seahorse::Client::NetworkingError => e
      raise translate(e)
    end

    # Returns a Token once the user has approved, or nil while they have not yet.
    # Terminal outcomes (denied, expired, wrong code) raise.
    def create_token(registration:, device_code:)
      resp = oidc.create_token(
        client_id: registration.client_id,
        client_secret: registration.client_secret,
        grant_type: "urn:ietf:params:oauth:grant-type:device_code",
        device_code: device_code
      )
      build_token(resp)
    rescue ::Aws::SSOOIDC::Errors::AuthorizationPendingException, ::Aws::SSOOIDC::Errors::SlowDownException
      nil
    rescue ::Aws::SSOOIDC::Errors::ServiceError, ::Seahorse::Client::NetworkingError => e
      raise translate(e)
    end

    def refresh_token(registration:, refresh_token:)
      resp = oidc.create_token(
        client_id: registration.client_id,
        client_secret: registration.client_secret,
        grant_type: "refresh_token",
        refresh_token: refresh_token
      )
      build_token(resp)
    rescue ::Aws::SSOOIDC::Errors::ServiceError, ::Seahorse::Client::NetworkingError => e
      raise translate(e)
    end

    # Portal calls take the cached access token verbatim; the SDK puts it in the
    # x-amz-sso_bearer_token header against portal.sso.<region>.amazonaws.com.
    def list_accounts(access_token:)
      each_page(:list_accounts) { |token| portal.list_accounts({ access_token: access_token, next_token: token }.compact) }
        .flat_map do |page|
          page.account_list.map do |a|
            Account.new(account_id: a.account_id, account_name: a.account_name, email: a.email_address)
          end
        end
    rescue ::Aws::SSO::Errors::ServiceError, ::Seahorse::Client::NetworkingError => e
      raise translate(e)
    end

    def list_account_roles(access_token:, account_id:)
      each_page(:list_account_roles) do |token|
        portal.list_account_roles({ access_token: access_token, account_id: account_id, next_token: token }.compact)
      end.flat_map { |page| page.role_list.map(&:role_name) }
    rescue ::Aws::SSO::Errors::ServiceError, ::Seahorse::Client::NetworkingError => e
      raise translate(e)
    end

    def role_credentials(access_token:, account_id:, role_name:)
      creds = portal.get_role_credentials(
        access_token: access_token, account_id: account_id, role_name: role_name
      ).role_credentials
      RoleCredentials.new(
        access_key_id: creds.access_key_id,
        secret_access_key: creds.secret_access_key,
        session_token: creds.session_token,
        # The portal returns epoch MILLIseconds, not seconds.
        expiration: Time.zone.at(creds.expiration.to_i / 1000)
      )
    rescue ::Aws::SSO::Errors::ServiceError, ::Seahorse::Client::NetworkingError => e
      raise translate(e)
    end

    private

    # Walks `next_token` to the end, bounded. A hit bound is logged rather than swallowed:
    # a truncated account list looks exactly like "your administrator did not grant you
    # that account", which is the wrong thing for a user to be told.
    def each_page(operation)
      pages = []
      token = nil

      MAX_PAGES.times do
        page = yield(token)
        pages << page
        token = page.next_token
        break if token.blank?
      end

      if token.present?
        Rails.logger.warn("[AwsSsoClient] #{operation} truncated at #{MAX_PAGES} pages; results are incomplete")
      end

      pages
    end

    def build_token(resp)
      Token.new(
        access_token: resp.access_token,
        refresh_token: resp.refresh_token,
        expires_at: Time.current + resp.expires_in.to_i.seconds
      )
    end

    def oidc
      @oidc ||= ::Aws::SSOOIDC::Client.new(region: @region, credentials: nil)
    end

    def portal
      @portal ||= ::Aws::SSO::Client.new(region: @region, credentials: nil)
    end

    # Never leak a vendor exception class to callers, and never put a response body in
    # the message — an OIDC error body can echo back the code being exchanged.
    def translate(error)
      # A networking failure carries no service code, and the overwhelmingly common cause
      # is a mistyped region: the endpoint host for `us-2-west` never resolves. Say that,
      # rather than surfacing `getaddrinfo` as a 500 the user cannot act on.
      if error.is_a?(::Seahorse::Client::NetworkingError)
        return Error.new("Could not reach AWS in region #{@region}. Check the region is a valid AWS region.")
      end

      klass =
        case error
        when ::Aws::SSOOIDC::Errors::ExpiredTokenException then ExpiredError
        when ::Aws::SSOOIDC::Errors::AccessDeniedException then DeniedError
        when ::Aws::SSOOIDC::Errors::InvalidClientException,
             ::Aws::SSOOIDC::Errors::InvalidGrantException then InvalidRegistrationError
        when ::Aws::SSO::Errors::UnauthorizedException then ExpiredError
        when ::Aws::SSO::Errors::ForbiddenException then DeniedError
        else Error
        end
      klass.new("#{error.class.name.demodulize}: #{error.code}")
    end
  end
end
