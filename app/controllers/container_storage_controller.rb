# frozen_string_literal: true

# Where a storage cannot sign its own URLs, an agent container puts a session archive
# here and fetches it back (Uploads::ContainerTransfer). The token in the query is the
# authentication: it names one object and one method, and expires.
class ContainerStorageController < ActionController::API
  MAX_BYTES = Sessions::Checkpoint::MAX_BYTES + 64.megabytes
  CHUNK_BYTES = 1.megabyte

  def update
    target = Uploads::ContainerTransfer.resolve(params[:token], method: "put")
    return head :not_found unless target
    return head :content_too_large if request.content_length.to_i > MAX_BYTES

    target.storage.upload(request.body, target.id)
    head :no_content
  end

  def show
    target = Uploads::ContainerTransfer.resolve(params[:token], method: "get")
    return head :not_found unless target&.storage&.exists?(target.id)

    io = target.storage.open(target.id)
    response.headers["Content-Type"] = "application/octet-stream"
    response.headers["Content-Length"] = io.size.to_s
    response.headers["Cache-Control"] = "no-store"
    self.response_body = Enumerator.new do |body|
      while (chunk = io.read(CHUNK_BYTES))
        body << chunk
      end
    ensure
      io.close
    end
  end
end
