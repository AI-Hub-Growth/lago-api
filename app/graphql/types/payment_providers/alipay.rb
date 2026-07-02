# frozen_string_literal: true

module Types
  module PaymentProviders
    class Alipay < Types::BaseObject
      graphql_name "AlipayProvider"

      field :code, String, null: false
      field :id, ID, null: false
      field :name, String, null: false

      field :alipay_public_key, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :app_id, String, null: true, permission: "organization:integrations:view"
      field :app_private_key, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :success_redirect_url, String, null: true, permission: "organization:integrations:view"
    end
  end
end
