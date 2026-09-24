# frozen_string_literal: true

module Web
  # Serves publicly shared files to anonymous visitors via a stable token: a
  # project asset, a workflow run output or a task attachment (PubliclyShareable).
  #
  # Safety model: the asset content is untrusted (an agent may have produced
  # arbitrary HTML/JS). `#show` renders our own viewer shell — embeddable
  # anywhere (frame-ancestors *) — which loads the raw content in a sandboxed
  # iframe. `#raw` streams the bytes through the app (not an S3 redirect) so we
  # can attach `Content-Security-Policy: sandbox`, forcing the browser to treat
  # the response as an opaque origin with scripts/forms/same-origin disabled.
  class PublicAssetsController < ApplicationController
    def show
      @asset = PubliclyShareable.find_shared(params[:token].to_s)
      return head(:not_found) unless @asset

      @raw_url = public_asset_raw_path(token: @asset.public_token)
      # Allow the share link to be embedded in third-party iframes; the raw
      # content it frames is sandboxed separately.
      response.headers.delete("X-Frame-Options")
      response.set_header("Content-Security-Policy", "frame-ancestors *")
      render layout: false
    end

    def raw
      asset = PubliclyShareable.find_shared(params[:token].to_s)
      file = asset&.shared_file
      return head(:not_found) unless file

      response.set_header("Content-Security-Policy", "sandbox")
      response.set_header("X-Content-Type-Options", "nosniff")

      # Streamed from storage in chunks: reading the file into the process first put
      # every anonymous download of a large asset into Puma's memory at once.
      status, headers, body = file.to_rack_response(
        type: asset.shared_content_type.presence || "application/octet-stream", disposition: "inline",
        filename: asset.name
      )
      headers.each { |name, value| response.headers[name] = value }
      self.status = status
      self.response_body = body
    end
  end
end
