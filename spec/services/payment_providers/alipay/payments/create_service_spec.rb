# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Alipay::Payments::CreateService do
  subject(:service_result) { described_class.call(payment:, reference: "Invoice QIN-001", metadata: {}) }

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
      amount_cents: 200_000,
      amount_currency: "CNY",
      provider_payment_id: nil,
      status: "pending",
      payable_payment_status: "pending"
    )
  end

  it "initializes a pending Alipay trade on the Lago payment" do
    expect(service_result).to be_success

    payment.reload
    expect(payment.provider_payment_id).to match(/\Ainv_[a-zA-Z0-9_]+\z/)
    expect(payment.provider_payment_id.length).to be <= 64
    expect(payment.status).to eq("WAIT_BUYER_PAY")
    expect(payment.payable_payment_status).to eq("processing")
  end

  context "when provider payment id is already present" do
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        payment_provider:,
        payment_provider_customer: provider_customer,
        organization:,
        customer:,
        amount_currency: "CNY",
        provider_payment_id: "inv_existing"
      )
    end

    it "keeps the existing merchant order number" do
      service_result

      expect(payment.reload.provider_payment_id).to eq("inv_existing")
    end
  end

  context "when the currency is not supported by Alipay page pay" do
    before { payment.update!(amount_currency: "USD") }

    it "returns a validation failure" do
      expect(service_result).not_to be_success
      expect(service_result.error.messages).to eq(base: ["unsupported_currency"])
    end
  end
end
