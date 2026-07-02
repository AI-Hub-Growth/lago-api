# frozen_string_literal: true

module CreditNotes
  module Refunds
    class AlipayCreateJob < ApplicationJob
      queue_as "providers"

      def perform(credit_note)
        result = CreditNotes::Refunds::AlipayService.new(credit_note).create
        result.raise_if_error!
      end
    end
  end
end
