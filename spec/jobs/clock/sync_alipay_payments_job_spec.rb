# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::SyncAlipayPaymentsJob do
  it "syncs pending Alipay payments" do
    allow(PaymentProviders::Alipay::Payments::SyncPendingService).to receive(:call!)

    described_class.perform_now

    expect(PaymentProviders::Alipay::Payments::SyncPendingService).to have_received(:call!)
  end
end
