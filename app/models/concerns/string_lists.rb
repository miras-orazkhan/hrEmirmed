module StringLists
  extend ActiveSupport::Concern

  class_methods do
    def validates_string_lists(*fields)
      validate do
        fields.each do |field|
          value = public_send(field)
          unless value.is_a?(Array) && value.size <= 100 && value.all? { |item| item.is_a?(String) && item.strip.present? && item.length <= 2_000 }
            errors.add(field, "must be an array of up to 100 nonempty strings (maximum 2000 characters each)")
          end
        end
      end
    end
  end
end
