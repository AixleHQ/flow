# frozen_string_literal: true

module Web
  # Serves publicly shared assets to anonymous visitors via a stable token.
  #
  # Safety model: the asset content is untrusted (an agent may have produced
  # arbitrary HTML/JS). `#show` renders our own viewer shell — embeddable
  # anywhere (frame-ancestors *) — which loads the raw content in a sandboxed
  # iframe. `#raw` streams the bytes through the app (not an S3 redirect) so we
  # can attach `Content-Security-Policy: sandbox`, forcing the browser to treat
  # the response as an opaque origin with scripts/forms/same-origin disabled.
  class PublicAssetsController < ApplicationController
    def show
      @asset = find_asset
      return head(:not_found) unless @asset

      @raw_url = public_asset_raw_path(token: @asset.public_token)
      # Allow the share link to be embedded in third-party iframes; the raw
      # content it frames is sandboxed separately.
      response.headers.delete("X-Frame-Options")
      response.set_header("Content-Security-Policy", "frame-ancestors *")
      render layout: false
    end

    def raw
      asset = find_asset
      return head(:not_found) unless asset

      version = asset.latest_version
      return head(:not_found) unless version&.file

      response.set_header("Content-Security-Policy", "sandbox")
      response.set_header("X-Content-Type-Options", "nosniff")

      content_type = version.content_type.presence || "application/octet-stream"
      data = version.file.download { |file| file.read }
      send_data data, type: content_type, disposition: "inline", filename: asset.name
    end

    private

    def find_asset
      token = params[:token].to_s
      return if token.blank?

      Asset.publicly_shared.find_by(public_token: token)
    end
  end
end
