# frozen_string_literal: true

module PaymentProviders
  module Alipay
    class HandleIncomingWebhookService < BaseService
      Result = BaseResult[:event]

      def initialize(organization_id:, params:, code: nil)
        @organization_id = organization_id
        @params = params.to_h.stringify_keys
        @code = code

        super
      end

      def call
        payment_provider_result = PaymentProviders::FindService.call(
          organization_id:,
          code:,
          payment_provider_type: "alipay"
        )
        return payment_provider_result unless payment_provider_result.success?

        payment_provider = payment_provider_result.payment_provider
        return invalid_webhook!("Unexpected app_id") if params["app_id"] != payment_provider.app_id
        return invalid_webhook!("Invalid signature") unless client(payment_provider).valid_notification?(params)

        PaymentProviders::Alipay::HandleEventJob.perform_later(
          organization: payment_provider.organization,
          event: params
        )

        result.event = params
        result
      end

      private

      attr_reader :organization_id, :params, :code

      def client(payment_provider)
        PaymentProviders::Alipay::Client.new(payment_provider:)
      end

      def invalid_webhook!(message)
        Rails.logger.warn(
          "Alipay webhook rejected organization_id=#{organization_id} code=#{code} " \
          "app_id=#{params["app_id"]} reason=#{message}"
        )

        result.service_failure!(code: "webhook_error", message:)
      end
    end
  end
end
