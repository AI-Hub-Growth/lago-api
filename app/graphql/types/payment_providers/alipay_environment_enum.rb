# frozen_string_literal: true

module Types
  module PaymentProviders
    class AlipayEnvironmentEnum < Types::BaseEnum
      ::PaymentProviders::AlipayProvider::ENVIRONMENTS.each do |environment|
        value environment
      end
    end
  end
end
