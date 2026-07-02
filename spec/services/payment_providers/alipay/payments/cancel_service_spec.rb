# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Alipay::Payments::CancelService do
  subject(:service_result) { described_class.call(payment:) }

  let(:organization) { create(:organization) }
  let(:payment_provider) { create(:alipay_provider, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:provider_customer) { create(:alipay_customer, customer:, organization:, payment_provider:) }
  let(:invoice) { create(:invoice, customer:, organization:, currency: "CNY") }
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      payment_provider:,
      payment_provider_customer: provider_customer,
      organization:,
      customer:,
      provider_payment_id: "inv_123",
      status: "WAIT_BUYER_PAY",
      payable_payment_status: "processing"
    )
  end
  let(:client) { instance_double(PaymentProviders::Alipay::Client) }

  before do
    allow(PaymentProviders::Alipay::Client).to receive(:new)
      .with(payment_provider:)
      .and_return(client)
  end

  context "when Alipay closes the trade" do
    before do
      allow(client).to receive(:close)
        .with(out_trade_no: "inv_123")
        .and_return("code" => "10000", "msg" => "Success")
    end

    it "marks the payment as failed locally" do
      expect(service_result).to be_success

      expect(payment.reload.status).to eq("TRADE_CLOSED")
      expect(payment.payable_payment_status).to eq("failed")
    end
  end

  context "when the trade cannot be closed because of its Alipay state" do
    before do
      allow(client).to receive(:close)
        .and_return(
          "code" => "40004",
          "sub_code" => "ACQ.TRADE_STATUS_ERROR",
          "sub_msg" => "Trade status is invalid"
        )
      allow(Rails.logger).to receive(:info)
    end

    it "logs and keeps the payment unchanged" do
      expect(service_result).to be_success

      expect(payment.reload.status).to eq("WAIT_BUYER_PAY")
      expect(payment.payable_payment_status).to eq("processing")
      expect(Rails.logger).to have_received(:info).with(a_string_matching(/Alipay payment not closeable/))
    end
  end

  context "when Alipay returns a blocking error" do
    before do
      allow(client).to receive(:close)
        .and_return(
          "code" => "40004",
          "sub_code" => "ACQ.INVALID_PARAMETER",
          "sub_msg" => "Invalid parameter"
        )
    end

    it "returns a service failure" do
      expect(service_result).not_to be_success
      expect(service_result.error.code).to eq("ACQ.INVALID_PARAMETER")
    end
  end
end
