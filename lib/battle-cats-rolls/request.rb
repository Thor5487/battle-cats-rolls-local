# frozen_string_literal: true

require 'rack'

module BattleCatsRolls
  class Request < Rack::Request
    # So that t=1&t=2 can be parsed as {"t" => [1, 2]}
    def parse_query(qs, d='&')
      query_parser.parse_query(qs, d)
    end
  end
end
