module Spree
  class SalesTaxRate < Spree::Base
    belongs_to :country, class_name: 'Spree::Country'
    belongs_to :state, class_name: 'Spree::State'

    validates_presence_of :country, :state, :zip_code, :rate
    validates_uniqueness_of :zip_code, scope: [:country, :state], case_sensitive: false

    self.whitelisted_ransackable_associations = %w[country state]
    self.whitelisted_ransackable_attributes = %w[zip_code]
  end
end