# frozen_string_literal: true

# Pull Docker Image Activity
# Downloads Docker image if not already cached
#
# Input: { image: "python:3.11" }
# Returns: { image: string, pulled: boolean }

module Activities
  class PullDockerImageActivity < Base
    PULL_TIMEOUT = 5.minutes

    def run(input)
      image = input.image
      raise ArgumentError, "image is required" if image.blank?

      log(:info, "Checking image: #{image}")

      # Check if image exists locally
      if image_exists?(image)
        log(:info, "Image already cached: #{image}")
        return { image: image, pulled: false }
      end

      # Pull image
      log(:info, "Pulling image: #{image}")
      pull_image(image)
      log(:info, "Image pulled successfully: #{image}")

      { image: image, pulled: true }
    rescue Docker::Error::NotFoundError => e
      log(:error, "Image not found: #{image}")
      raise TemporalExceptions.wrap(e, retryable: false)
    rescue Docker::Error::TimeoutError => e
      log(:error, "Timeout pulling image: #{image}")
      raise TemporalExceptions.wrap(e, retryable: true)
    rescue StandardError => e
      log(:error, "Failed to pull image: #{e.message}")
      raise TemporalExceptions.wrap(e, retryable: true)
    end

    private

    def image_exists?(image)
      Docker::Image.get(image)
      true
    rescue Docker::Error::NotFoundError
      false
    end

    def pull_image(image)
      Timeout.timeout(PULL_TIMEOUT) do
        Docker::Image.create("fromImage" => image)
      end
    end
  end
end
