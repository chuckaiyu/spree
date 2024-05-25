module Spree
  class Calculator::SalesTax < Calculator
    include VatPriceCalculation

    attr_accessor :tax_rate

    def self.description
      Spree.t(:sales_tax)
    end

    # Default tax calculator still needs to support orders for legacy reasons
    # Orders created before Spree 2.1 had tax adjustments applied to the order, as a whole.
    # Orders created with Spree 2.2 and after, have them applied to the line items individually.
    # def compute_order(order)
    #   debugger
    #   matched_line_items = order.line_items.select do |line_item|
    #     line_item.tax_category == calculable.tax_category
    #   end

    #   line_items_total = matched_line_items.sum(&:total)
    #   if calculable.included_in_price
    #     round_to_two_places(line_items_total - (line_items_total / (1 + default_tax_rate)))
    #   else
    #     round_to_two_places(line_items_total * default_tax_rate)
    #   end
    # end

    # When it comes to computing shipments or line items: same same.
    def compute_shipment_or_line_item(item)
      address = item&.order&.tax_address
      @tax_rate = tax_rate_by_address(address)

      if calculable.included_in_price
        deduced_total_by_rate(item.pre_tax_amount, tax_rate)
      else
        round_to_two_places(item.discounted_amount * tax_rate)
      end
    end

    alias compute_shipment compute_shipment_or_line_item
    alias compute_line_item compute_shipment_or_line_item

    def compute_shipping_rate(shipping_rate)
      address = shipping_rate&.order&.tax_address
      @tax_rate = tax_rate_by_address(address)

      if calculable.included_in_price
        pre_tax_amount = shipping_rate.cost / (1 + tax_rate)
        deduced_total_by_rate(pre_tax_amount, tax_rate)
      else
        with_tax_amount = shipping_rate.cost * tax_rate
        round_to_two_places(with_tax_amount)
      end
    end

    private

    def default_tax_rate
      calculable.amount
    end

    def tax_rate_by_address(address)
      if (address && address.country_id && address.state_id && address.zipcode)
        sales_tax = Spree::SalesTaxRate.find_by(country_id: address.country_id, state_id: address.state_id, zip_code: address.zipcode)
        if sales_tax
          sales_tax.rate
        else
          default_tax_rate
        end
      else
        default_tax_rate
      end
    end

    def deduced_total_by_rate(pre_tax_amount, rate)
      round_to_two_places(pre_tax_amount * rate)
    end
  end
end
