require "csv"

module Spree
  module Calculator::Shipping
    class PricePerKg < ShippingCalculator
      preference :data, :text
      preference :currency, :string, default: -> { Spree::Store.default.default_currency }
      preference :amount, :decimal, default: 0

      def self.description
        Spree.t(:shipping_price_per_kg)
      end

      def compute_package(package)
        total_weight = 0
        package.contents.each do |item|
          if item.volume && item.volume > 0
            volume_weight = item.volume / volume_factor
            total_weight += volume_weight > item.weight ? volume_weight : item.weight
          else
            total_weight += item.weight
          end
        end

        total_amount = compute_from_weight(total_weight)
        if total_amount > 0
          total_amount
        else
          compute_from_quantity(package.contents.sum(&:quantity))
        end
      end

      def compute_from_weight(weight)
        if weight
          rules.each do |row|
            if compare(row["condition"], weight)
              return calculate(row, weight)
            end
          end
        else
          return 0
        end
      end

      def compute_from_quantity(quantity)
        preferred_amount * quantity
      end

      def rules
        @rules ||= CSV.parse(preferred_data, headers: :first_row, skip_blanks: true)
      end

      def volume_factor
        @volume_factor ||= rules&.first && rules.first["factor"] ? BigDecimal(rules.first["factor"]) : 0
      end
      
      def calculate(row, weight)
        precision = (row["precision"]).to_i
        minimum = BigDecimal(row["minimum"])
        price = BigDecimal(row["price"])
        overweight = BigDecimal(row["overweight"])
        handling_fee = BigDecimal(row["handling_fee"])

        if weight < minimum
          weight = minimum
        end

        if overweight && overweight > 0 && weight > 1
          other_weight = weight - 1
          price + other_weight.ceil(precision) * overweight + handling_fee
        else
          weight.ceil(precision) * price + handling_fee
        end
      end

      def compare(condition, weight)
        gram_value = convert_to_gram(weight)
        result = /^(\d+[\.\d]*)([W<≤]{3})(\d+[\.\d]*)\Z/.match(condition)
        left_value = convert_to_gram(result[1])
        right_value = convert_to_gram(result[3])

        case result[2]
        when "<W≤"
          left_value < gram_value && gram_value <= right_value
        when "≤W<"
          left_value <= gram_value && gram_value < right_value
        when "≤W≤"
          left_value <= gram_value && gram_value <= right_value
        else
          false
        end
      end

      def convert_to_gram(kilogram)
        kilogram ? (BigDecimal(kilogram.to_s) * 1000).to_i : 0
      end
    end
  end
end