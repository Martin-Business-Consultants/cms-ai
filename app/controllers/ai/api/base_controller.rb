# frozen_string_literal: true

module Ai
  module Api
    # The plugin's API (/api/ai…): a 404 while it's off, every action declaring its capability.
    class BaseController < ::Api::BaseController
      include PluginGated
      plugin :ai
      enforce_authorization
    end
  end
end
