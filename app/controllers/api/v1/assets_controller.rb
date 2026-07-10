# frozen_string_literal: true

module Api
  module V1
    class AssetsController < ApplicationController
      # @summary Generate a presigned URL for direct file upload
      def presign
        if Rails.env.development? || Rails.env.test?
          uid = SecureRandom.hex(30)
          render json: {
            method: "POST",
            url: upload_api_v1_assets_path,
            fields: { key: "cache/#{uid}" },
            headers: {}
          }
        else
          storage = Shrine.storages[:cache]
          extension = File.extname(params[:filename].to_s)
          uid = "#{SecureRandom.hex(30)}#{extension}"
          presign_data = storage.presign(uid,
            content_type: params[:type],
            # Inline disposition is safe here: user assets are served from an
            # isolated S3 bucket origin (palad-assets-prod.s3.amazonaws.com), not
            # an app subdomain, so an inline HTML/SVG asset's scripts run in that
            # separate origin with no access to app cookies/session (F32 accepted
            # as low-risk). Re-add a download/sandbox disposition IF user assets
            # ever move behind an app subdomain (e.g. static.flow.aixle.com).
            content_disposition: ::ContentDisposition.inline(params[:filename]),
            content_length_range: 0..(1024 * 1024 * 1024)
          )
          render json: {
            method: "POST",
            url: presign_data[:url],
            fields: presign_data[:fields] || {},
            headers: presign_data[:headers] || {}
          }
        end
      end

      # @summary Upload a file to temporary cache storage
      def upload
        _status, headers, body = AssetFileUploader.upload_response(:cache, request.env)
        uploaded_file = Hashie::Mash.new(JSON.parse(body.first))
        updated_headers = headers.merge({
          Location: uploaded_file.url,
          ETag: nil
        })

        updated_headers.each do |key, value|
          response.headers[key] = value
        end

        head :no_content
      end
    end
  end
end
