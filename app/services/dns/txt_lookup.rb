# frozen_string_literal: true

module Dns
  # The one place this application reads DNS.
  #
  # An adapter rather than a call to Resolv at the point of use, so the thing
  # that decides whether a customer owns a domain can be driven in a test without
  # a network, and so a resolver that hangs cannot hang a web request.
  module TxtLookup
    # A nameserver that does not answer must not hold a request open: the person
    # clicking "check now" is waiting on it.
    TIMEOUT = 5

    class << self
      # Every TXT record at the host, each already joined from its character
      # strings — a value longer than 255 bytes arrives split, and a caller
      # comparing against a token would never match the halves.
      def call(host)
        resolver.call(host)
      end

      # Swapped for a fake in tests. Nothing else may reach a nameserver.
      attr_writer :resolver

      def resolver
        @resolver ||= method(:resolve)
      end

      private

      def resolve(host)
        Resolv::DNS.open do |dns|
          dns.timeouts = TIMEOUT
          dns.getresources(host.to_s, Resolv::DNS::Resource::IN::TXT).map { |record| record.strings.join }
        end
      rescue Resolv::ResolvError, Resolv::ResolvTimeout, IOError, SystemCallError => e
        # A domain with no such record, a nameserver that refused, a network that
        # is not there: all of them mean "not proved", none of them mean "broken".
        Rails.logger.info("[Dns::TxtLookup] #{host}: #{e.class} #{e.message}")
        []
      end
    end
  end
end
