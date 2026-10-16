# frozen_string_literal: true

module Bitbucket
  module Forge
    # Connect, from both ends (docs/design/bitbucket-integration.md §5.5). A
    # workspace administrator starts it on the app's settings page; a signed-in
    # Aixle user who may manage the project's integrations confirms it.
    module Pairing
      class Refused < StandardError
        attr_reader :code

        def initialize(message, code:)
          super(message)
          @code = code
        end
      end

      NOT_ADMIN = "Only a Bitbucket workspace administrator can connect this workspace to Aixle."
      SPENT = "This link was already used or has expired. Start again in Bitbucket."

      module_function

      # The link the administrator's browser opens. The secret travels in the
      # fragment, so no server log on the way sees it.
      def start!(installation:, account_id:)
        raise Refused.new(NOT_ADMIN, code: "not_workspace_admin") unless WorkspaceAdmin.admin?(installation, account_id)

        pairing, secret = BitbucketPairing.start!(installation: installation, account_id: account_id)
        "#{Settings.protocol || 'https'}://#{Settings.domain}/integrations/bitbucket/connect#pairing=#{pairing.public_id}.#{secret}"
      end

      # Binds the workspace to the project's company (or finds it already bound
      # there) and connects the project. The caller has checked that `user` may
      # manage the project's integrations.
      def confirm!(pairing:, user:, project:)
        BitbucketPairing.transaction do
          lock_live!(pairing)

          installation = pairing.bitbucket_installation
          installation.lock!
          bind!(installation, project, user)
          Connection.restore!(installation)
          integration = Connection.connect!(installation: installation, project: project, user: user)
          pairing.destroy!
          integration
        end
      end

      # A confirmed pairing is deleted, so a second confirmation racing the first
      # finds no row to lock.
      def lock_live!(pairing)
        raise Refused.new(SPENT, code: "expired") if pairing.destroyed?

        pairing.lock!
        raise Refused.new(SPENT, code: "expired") if pairing.expires_at <= Time.current
      rescue ActiveRecord::RecordNotFound
        raise Refused.new(SPENT, code: "expired")
      end

      def bind!(installation, project, user)
        raise Refused.new(Installations::REMOVED, code: "uninstalled") unless installation.status.active?
        return if installation.company_id == project.company_id

        if installation.bound?
          raise Refused.new("This Bitbucket workspace is already connected to another Aixle company. A workspace " \
                            "administrator can disconnect it from Workspace settings → Aixle Flow first.",
                            code: "bound_elsewhere")
        end

        installation.update!(company_id: project.company_id, bound_by: user, bound_at: Time.current)
      end

      # What the settings page shows a workspace administrator.
      def status(installation)
        bound = installation.bound?
        projects = bound ? installation.integrations.where(company_id: installation.company_id).includes(:project) : []
        {
          ok: true, bound: bound,
          workspace: { slug: installation.workspace_slug, name: installation.workspace_name },
          company: bound ? installation.company&.name : nil,
          projects: projects.filter_map { |integration| integration.project&.name }.uniq.sort,
          bound_by: bound ? installation.bound_by&.email : nil,
          bound_at: bound ? installation.bound_at&.iso8601 : nil
        }
      end
    end
  end
end
