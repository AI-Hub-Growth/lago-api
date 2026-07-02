# frozen_string_literal: true

module PaymentProviders
  module Alipay
    class HandleEventJob < ApplicationJob
      queue_as do
        if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
          :payments
        else
          :providers
        end
      end

      def perform(organization:, event:)
        PaymentProviders::Alipay::HandleEventService.call!(
          organization:,
          event:
        )
      end
    end
  end
end
