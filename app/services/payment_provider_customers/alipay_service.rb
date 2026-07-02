# frozen_string_literal: true

module PaymentProviderCustomers
  class AlipayService < BaseService
    def initialize(alipay_customer = nil)
      @alipay_customer = alipay_customer

      super(nil)
    end

    def create
      result.alipay_customer = alipay_customer
      result
    end

    def update
      result
    end

    def generate_checkout_url(send_webhook: true)
      result.not_allowed_failure!(code: "feature_not_supported")
    end

    private

    attr_reader :alipay_customer
  end
end
