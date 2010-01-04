module ActiveMerchant
  module Shipping
    module Base
      mattr_accessor :mode
      self.mode = :production
      
      def self.carrier(name)
        result = ActiveMerchant::Shipping::Carriers.all.find {|c| c.name.casecmp(name.to_s) == 0}
        raise NameError if result.nil?
        result
      end
    end
  end
end
