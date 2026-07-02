# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::Refunds::AlipayCreateJob do
  let(:credit_note) { create(:credit_note) }

  let(:refund_service) do
    instance_double(CreditNotes::Refunds::AlipayService)
  end

  it "delegates to the Alipay refund service" do
    allow(CreditNotes::Refunds::AlipayService).to receive(:new)
      .with(credit_note)
      .and_return(refund_service)
    allow(refund_service).to receive(:create)
      .and_return(BaseService::Result.new)

    described_class.perform_now(credit_note)

    expect(CreditNotes::Refunds::AlipayService).to have_received(:new)
    expect(refund_service).to have_received(:create)
  end
end
