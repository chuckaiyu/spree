
module Spree
  module Api
    module V2
      module Platform
        class PaypalCheckoutOrderSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :payment_method
          belongs_to :user
        end
      end
    end
  end
end