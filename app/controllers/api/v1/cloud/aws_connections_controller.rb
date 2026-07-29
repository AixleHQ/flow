# frozen_string_literal: true

module Api
  module V1
    module Cloud
      # Drives the AWS Identity Center device flow from the browser: create → poll →
      # complete. The whole exchange happens server-side; the browser only shows the
      # verification link and, once approved, picks an account and role.
      #
      # The verification URL is passed through verbatim. It must never be constructed or
      # rewritten — the documented device.sso.<region> host does not resolve, and real
      # instances return per-instance portal hosts.
      class AwsConnectionsController < ApplicationController
        rescue_from CloudAuth::Error, with: :render_cloud_auth_error

        def show
          render json: connection_state
        end

        def create
          return missing(:start_url) if params[:start_url].blank?
          return missing(:sso_region) if params[:sso_region].blank?
          return no_company if current_company.nil?

          started = flow.start(start_url: params[:start_url], sso_region: params[:sso_region])
          render json: {
            handle: started.handle,
            verification_url: started.verification_uri_complete,
            user_code: started.user_code,
            interval: started.interval,
            expires_in: started.expires_in
          }, status: :created
        end

        def poll
          return missing(:handle) if params[:handle].blank?

          result = flow.poll(handle: params[:handle])
          if result.is_a?(CloudAuth::AwsDeviceFlow::Pending)
            render json: { status: "pending", interval: result.interval }
          else
            render json: { status: "approved", accounts: serialize_accounts(result.accounts) }
          end
        end

        def complete
          %i[handle account_id role_name region].each do |key|
            return missing(key) if params[key].blank?
          end

          # The profile NAME is caller-supplied on purpose. A repo may ship its own
          # committed .claude/settings.json pinning AWS_PROFILE (project settings outrank
          # the user settings we write), and that pin has to resolve to the profile we
          # put in ~/.aws/config or Claude Code looks for one that does not exist.
          flow.finish(handle: params[:handle], account_id: params[:account_id],
                      role_name: params[:role_name], region: params[:region],
                      **(params[:profile].present? ? { profile: params[:profile] } : {}))
          render json: connection_state
        end

        # Deliberately 200 even when the connection is broken: a failed probe is a
        # successful diagnosis, and the payload carries the provider's own wording.
        def health
          result = CloudAuth::AwsHealthCheck.new(user: current_user, company: current_company).call
          render json: {
            ok: result.ok?,
            stage: result.stage,
            model_id: result.model_id,
            error_code: result.error_code,
            error_message: result.error_message
          }
        end

        def destroy
          credential = connected_credential
          if credential
            config = credential.config_data
            config.delete(Agents::ClaudeCodeAdapter::BEDROCK_KEY)
            credential.config_data = config
            credential.save!
          end
          render json: connection_state
        end

        private

        # Scoped to the company the user is acting for: the connection lands on that
        # company's credential and its Bedrock spend is billed there.
        def flow
          CloudAuth::AwsDeviceFlow.new(user: current_user, company: current_company)
        end

        def connected_credential
          CloudAuth::CredentialLookup.claude_code(user_id: current_user.id, company_id: current_company&.id)
        end

        def serialize_accounts(accounts)
          accounts.map do |account|
            { account_id: account.account_id, account_name: account.account_name, roles: account.roles }
          end
        end

        # Reports what the container will actually get, plus why it is unusable when it
        # is — the same reason codes Preflight uses at session start.
        def connection_state
          credential = connected_credential
          block = credential && credential.config_data[Agents::ClaudeCodeAdapter::BEDROCK_KEY]
          return { connected: false } unless block.is_a?(Hash)

          idc = block["identity_center"] || {}
          {
            connected: CloudAuth::Preflight.unusable_reason(block).nil?,
            reason: CloudAuth::Preflight.unusable_reason(block),
            region: block["region"],
            profile: block["profile"],
            account_id: idc["account_id"],
            role_name: idc["role_name"],
            start_url: idc["start_url"]
          }
        end

        def missing(key)
          render json: { error: "missing_parameter", message: "#{key} is required" },
                 status: :unprocessable_entity
        end

        # A connection is billed to a company, so a caller acting for none (a super admin
        # with no membership) has nowhere to put one.
        def no_company
          render json: { error: "no_company", message: "no active company for this user" },
                 status: :unprocessable_entity
        end

        def render_cloud_auth_error(error)
          render json: { error: error.class.name.demodulize.underscore, message: error.message },
                 status: cloud_auth_status(error)
        end

        # A dead authorization is not the caller's fault and is not retryable with the
        # same handle: 410 tells the UI to restart the flow rather than keep polling.
        def cloud_auth_status(error)
          case error
          when CloudAuth::DeniedError then :forbidden
          when CloudAuth::ExpiredError, CloudAuth::InvalidRegistrationError then :gone
          else :unprocessable_entity
          end
        end
      end
    end
  end
end
