# frozen_string_literal: true

module PaymentProviderCustomers
  class AlipayCustomer < BaseCustomer
    def require_provider_payment_id?
      false
    end
  end
end

# == Schema Information
#
# Table name: payment_provider_customers
# Database name: primary
#
#  id                   :uuid             not null, primary key
#  deleted_at           :datetime
#  settings             :jsonb            not null
#  type                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :uuid             not null
#  organization_id      :uuid             not null
#  payment_provider_id  :uuid
#  provider_customer_id :string
#
