# frozen_string_literal: true

module Api
  module V1
    class AssetsController < ApplicationController
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
          uid = "#{SecureRandom.hex(30)}/#{params[:filename]}"
          presign_data = storage.presign(uid,
            content_type: params[:type],
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

      def upload
        status, headers, body = AssetFileUploader.upload_response(:cache, request.env)
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
