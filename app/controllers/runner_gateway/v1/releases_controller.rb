# frozen_string_literal: true

module RunnerGateway
  module V1
    # `GET /runner/v1/releases/:version/:platform` and
    # `GET /runner/v1/releases/:version/checksums`
    # (docs/design/agent-runtimes/DESIGN.md §14.3, runner/protocol/PROTOCOL.md
    # §5.6, §5.7): the platform's own URL of a runner binary, the only one an
    # installer or a self-updating runner knows. The redirect points at the
    # `runner-v*` release's asset and carries the digest from the platform's
    # pins (config/runner_release.yml), and the checksums answer the same
    # digests, so an asset changed on the asset host fails verification.
    #
    # Public: no token and no protocol headers, since an operator downloads
    # the binary before the machine has either. A version or platform the pins
    # do not list is `404 not_found`, so nothing unpinned is ever served.
    class ReleasesController < ApplicationController
      skip_before_action :check_protocol

      before_action :check_params

      def show
        binary = Runners::Release.binary(params[:version], params[:platform])
        return not_pinned if binary.nil?

        response.set_header("Cache-Control", "no-store")
        response.set_header("X-Aixle-Runner-Sha256", binary.sha256)
        redirect_to binary.url, status: :found, allow_other_host: true
      end

      def checksums
        checksums = Runners::Release.checksums(params[:version])
        return not_pinned if checksums.nil?

        response.set_header("Cache-Control", "no-store")
        render json: RunnerGatewayChecksumsResource.new(checksums).to_h
      end

      private

      def check_params
        return if Runners::ProtocolSchema.valid?("releases.params", params.permit(:version, :platform).to_h)

        refuse(:bad_request, "invalid_request",
               "`version` must be a semantic version such as 0.1.0, and the platform `<os>-<arch>` such as linux-amd64.")
      end

      def not_pinned
        refuse(:not_found, "not_found", "The platform pins no such runner release.")
      end
    end
  end
end
