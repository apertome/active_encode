require 'rails'

module ActiveEncode
  class Engine < ::Rails::Engine
    isolate_namespace ActiveEncode
  end
end
