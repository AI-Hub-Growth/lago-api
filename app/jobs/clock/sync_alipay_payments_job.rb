# frozen_string_literal: true

module Clock
  class SyncAlipayPaymentsJob < ClockJob
    def perform
      PaymentProviders::Alipay::Payments::SyncPendingService.call!
    end
  end
end
