# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Alipay::HandleIncomingWebhookService do
  subject(:service_call) do
    described_class.call(
      organization_id: organization.id,
      code: payment_provider.code,
      params: params
    )
  end

  let(:organization) { create(:organization) }
  let(:payment_provider) { create(:alipay_provider, organization:, app_id: "9021000158636207") }
  let(:params) do
    {
      "app_id" => payment_provider.app_id,
      "out_trade_no" => "inv_123",
      "trade_status" => "TRADE_SUCCESS",
      "sign" => "signature"
    }
  end
  let(:client) { instance_double(PaymentProviders::Alipay::Client) }

  before do
    allow(PaymentProviders::Alipay::Client).to receive(:new)
      .with(payment_provider:)
      .and_return(client)
    allow(client).to receive(:valid_notification?).with(params).and_return(true)
    allow(PaymentProviders::Alipay::HandleEventService).to receive(:call)
      .with(organization:, event: params)
      .and_return(BaseService::Result.new)
  end

  it "processes the Alipay event before returning success" do
    result = service_call

    expect(result).to be_success
    expect(result.event).to eq(params)
    expect(PaymentProviders::Alipay::HandleEventService).to have_received(:call)
      .with(organization:, event: params)
  end

  context "when the event cannot be processed" do
    before do
      allow(PaymentProviders::Alipay::HandleEventService).to receive(:call)
        .with(organization:, event: params)
        .and_return(
          BaseService::Result.new.service_failure!(
            code: "invalid_payment_amount",
            message: "Alipay total_amount does not match the Lago payment amount"
          )
        )
    end

    it "rejects the webhook so Alipay can retry" do
      result = service_call

      expect(result).not_to be_success
      expect(result.error.code).to eq("webhook_error")
      expect(result.error.error_message).to include("Failed to process event")
    end
  end

  context "when the signature is invalid" do
    before do
      allow(client).to receive(:valid_notification?).with(params).and_return(false)
    end

    it "does not process the event" do
      result = service_call

      expect(result).not_to be_success
      expect(result.error.code).to eq("webhook_error")
      expect(PaymentProviders::Alipay::HandleEventService).not_to have_received(:call)
    end
  end
end
