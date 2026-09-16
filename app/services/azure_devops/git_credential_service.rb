# frozen_string_literal: true

module AzureDevops
  # Resolves Git authentication for one attached repository inside one live
  # session. Everything the credential endpoint is allowed to assume is checked
  # here, in order, before any token is minted.
  #
  # The chain matters more than any single link: a repository id is not proof of
  # session attachment, session attachment is not proof of project access,
  # project access is not proof that the connection is still active, an active
  # connection is not proof that the company still holds an approved binding,
  # and an approved binding is not proof that the selected Azure project is
  # still inside it. Each of those has its own failure mode and each is checked.
  class GitCredentialService
    Vended = Struct.new(:scheme, :username, :token, :expires_in, :clone_url, :repository_id, keyword_init: true) do
      def to_h
        { scheme: scheme, username: username, password: token, expires_in: expires_in,
          url: clone_url, repository_id: repository_id }.compact
      end
    end

    def initialize(session)
      @session = session
    end

    attr_reader :session

    # `repository_id` is the LOCAL Aixle id the helper was configured with, not
    # anything the remote URL carries — so a rewritten remote cannot ask for
    # another repository's credentials.
    def vend!(repository_id:, requested_url: nil)
      raise IntegrationUnavailable, "Session is not active" unless session&.active?

      repository = session.repositories.find_by(id: repository_id)
      raise NotAuthorized, "Repository #{repository_id} is not attached to this session" if repository.nil?
      raise NotAuthorized, "Repository #{repository_id} is not an Azure DevOps repository" unless repository.azure_devops?

      integration = repository.integration
      unless integration.project_id == session.project_id && integration.company_id == session.project&.company_id
        raise NotAuthorized, "Repository #{repository_id} belongs to another project"
      end

      verify_requested_url!(repository, requested_url)

      # The repository's OWN project, not the connection's. A connection covers
      # several, so resolving without one is refused rather than guessed — which
      # is how a clone on a two-project connection came back as
      # "Azure credential unavailable (validation_failed)" with an empty
      # workspace and no other clue.
      resolved = CredentialProvider.resolve!(integration, capability: :"repositories.read",
                                             project_id: repository.external_project_id)
      verify_repository_scope!(repository, resolved)

      credential = resolved.git_credential
      Vended.new(
        scheme: credential[:scheme],
        username: credential[:username],
        token: credential[:token],
        expires_in: credential[:expires_in],
        clone_url: repository.clone_url,
        repository_id: repository.id
      )
    end

    # The Azure identity recorded on the row must still match the connection's
    # approved scope. A project moved out of the approved list, or an
    # integration re-pointed at a different Azure project, has to stop vending
    # for repositories the old scope covered.
    def verify_repository_scope!(repository, resolved)
      return if repository.external_project_id.present? && repository.external_project_id == resolved.project_id

      raise NotAuthorized, "Repository #{repository.id} is outside this connection's Azure project"
    end

    private

    # Git tells the helper which URL it is authenticating. When it does, the
    # host and organization must be the ones on the row: a helper invoked for
    # some other host must not be answered with an Azure token.
    def verify_requested_url!(repository, requested_url)
      return if requested_url.blank?

      requested = parse(requested_url)
      stored = parse(repository.clone_url)
      raise NotAuthorized, "Unrecognized credential request" if requested.nil? || stored.nil?

      same_host = requested.host == stored.host
      same_org = requested.path.to_s.split("/").reject(&:blank?).first == stored.path.to_s.split("/").reject(&:blank?).first
      return if same_host && same_org

      raise NotAuthorized, "Credential request does not match repository #{repository.id}"
    end

    # Git hands the helper a DECODED path, so an organization, project or
    # repository whose name contains a space arrives as
    # ".../Aixle Flow Example/_git/..." — which `URI.parse` refuses outright.
    # That refusal came back as "Unrecognized credential request", a 403, and a
    # push that could not authenticate, on every repository with a space in its
    # name. Normalizing here rather than in the helper means any caller gets it,
    # and a URL that is already encoded is left exactly as it is.
    def parse(url)
      uri = begin
        URI.parse(url.to_s)
      rescue URI::InvalidURIError
        begin
          URI.parse(URI::DEFAULT_PARSER.escape(url.to_s))
        rescue URI::InvalidURIError
          nil
        end
      end
      uri.is_a?(URI::HTTPS) ? uri : nil
    end
  end
end
