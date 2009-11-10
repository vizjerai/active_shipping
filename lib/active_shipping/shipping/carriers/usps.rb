# -*- encoding: utf-8 -*-
require 'cgi'

module ActiveMerchant
  module Shipping

    # After getting an API login from USPS (looks like '123YOURNAME456'),
    # run the following test:
    # 
    # usps = USPS.new(:login => '123YOURNAME456', :test => true)
    # usps.valid_credentials?
    #
    # This will send a test request to the USPS test servers, which they ask you
    # to do before they put your API key in production mode.
    class USPS < Carrier
      self.retry_safe = true

      cattr_reader :name
      @@name = "USPS"

      LIVE_DOMAIN = 'production.shippingapis.com'
      LIVE_RESOURCE = 'ShippingAPI.dll'

      TEST_DOMAINS = { #indexed by security; e.g. TEST_DOMAINS[USE_SSL[:rates]]
        true => 'secure.shippingapis.com',
        false => 'testing.shippingapis.com'
      }

      TEST_RESOURCE = 'ShippingAPITest.dll'

      API_CODES = {
        :us_rates => 'RateV3',
        :world_rates => 'IntlRate',
        :test => 'CarrierPickupAvailability'
      }
      USE_SSL = {
        :us_rates => false,
        :world_rates => false,
        :test => true
      }
      CONTAINERS = {
        :envelope => 'Flat Rate Envelope',
        :box => 'Flat Rate Box'
      }
      MAIL_TYPES = {
        :package => 'Package',
        :postcard => 'Postcards or aerogrammes',
        :matter_for_the_blind => 'Matter for the blind',
        :envelope => 'Envelope'
      }
      PACKAGE_PROPERTIES = {
        'ZipOrigination' => :origin_zip,
        'ZipDestination' => :destination_zip,
        'Pounds' => :pounds,
        'Ounces' => :ounces,
        'Container' => :container,
        'Size' => :size,
        'Machinable' => :machinable,
        'Zone' => :zone,
        'Postage' => :postage,
        'Restrictions' => :restrictions
      }
      POSTAGE_PROPERTIES = {
        'MailService' => :service,
        'Rate' => :rate
      }
      US_SERVICES = {
        :first_class => 'FIRST CLASS',
        :priority => 'PRIORITY',
        :express => 'EXPRESS',
        :bpm => 'BPM',
        :parcel => 'PARCEL',
        :media => 'MEDIA',
        :library => 'LIBRARY',
        :all => 'ALL'
      }

      # TODO: get rates for "U.S. possessions and Trust Territories" like Guam, etc. via domestic rates API: http://www.usps.com/ncsc/lookups/abbr_state.txt
      # TODO: figure out how USPS likes to say "Ivory Coast"
      #
      # Country names:
      # http://pe.usps.gov/text/Imm/immctry.htm
      COUNTRY_NAME_CONVERSIONS = {
        "BA" => "Bosnia-Herzegovina",
        "CD" => "Congo, Democratic Republic of the",
        "CG" => "Congo (Brazzaville),Republic of the",
        "CI" => "Côte d'Ivoire (Ivory Coast)",
        "CK" => "Cook Islands (New Zealand)",
        "FK" => "Falkland Islands",
        "GB" => "Great Britain and Northern Ireland",
        "GE" => "Georgia, Republic of",
        "IR" => "Iran",
        "KN" => "Saint Kitts (St. Christopher and Nevis)",
        "KP" => "North Korea (Korea, Democratic People's Republic of)",
        "KR" => "South Korea (Korea, Republic of)",
        "LA" => "Laos",
        "LY" => "Libya",
        "MC" => "Monaco (France)",
        "MD" => "Moldova",
        "MK" => "Macedonia, Republic of",
        "MM" => "Burma",
        "PN" => "Pitcairn Island",
        "RU" => "Russia",
        "SK" => "Slovak Republic",
        "TK" => "Tokelau (Union) Group (Western Samoa)",
        "TW" => "Taiwan",
        "TZ" => "Tanzania",
        "VA" => "Vatican City",
        "VG" => "British Virgin Islands",
        "VN" => "Vietnam",
        "WF" => "Wallis and Futuna Islands",
        "WS" => "Western Samoa"
      }

      def self.size_code_for(package)
        total = package.inches(:length) + package.inches(:girth)
        if total <= 84
          return 'REGULAR'
        elsif total <= 108
          return 'LARGE'
        else # <= 130
          return 'OVERSIZE'
        end
      end

      # from info at http://www.usps.com/businessmail101/mailcharacteristics/parcels.htm
      # 
      # package.options[:books] -- 25 lb. limit instead of 35 for books or other printed matter.
      #                             Defaults to false.
      def self.package_machinable?(package, options={})
        at_least_minimum =  package.inches(:length) >= 6.0 &&
                            package.inches(:width) >= 3.0 &&
                            package.inches(:height) >= 0.25 &&
                            package.ounces >= 6.0
        at_most_maximum  =  package.inches(:length) <= 34.0 &&
                            package.inches(:width) <= 17.0 &&
                            package.inches(:height) <= 17.0 &&
                            package.pounds <= (package.options[:books] ? 25.0 : 35.0)
        at_least_minimum && at_most_maximum
      end

      def requirements
        [:login]
      end

      def find_rates(origin, destination, packages, options = {})
        options = @options.merge(options)
        
        origin = Location.from(origin)
        destination = Location.from(destination)
        packages = Array(packages)

        #raise ArgumentError.new("USPS packages must originate in the U.S.") unless ['US',nil].include?(origin.country_code(:alpha2))

        # domestic or international?
        rates = nil
        response = if ['US',nil].include?(destination.country_code(:alpha2))
          rates = us_rates(origin, destination, packages, options)
        else
          rates = world_rates(origin, destination, packages, options)
        end
        rates
      end

      def valid_credentials?
        # Cannot test with find_rates because USPS doesn't allow that in test mode
        test_mode? ? canned_address_verification_works? : super
      end

      def maximum_weight
        Mass.new(70, :pounds)
      end

      protected

      def us_rates(origin, destination, packages, options={})
        request = build_us_rate_request(packages, origin.zip, destination.zip, options)
        response = commit(:us_rates, URI.encode(save_request(request)), false)
         # never use test mode; rate requests just won't work on test servers
        parse_rate_response(origin, destination, packages, response, options)
      end

      def world_rates(origin, destination, packages, options={})
        request = build_world_rate_request(packages, destination.country, options)
        response = commit(:world_rates, URI.encode(save_request(request)), false)
         # never use test mode; rate requests just won't work on test servers
        parse_rate_response(origin, destination, packages, response, options)
      end

      # Once the address verification API is implemented, remove this and have valid_credentials? build the request using that instead.
      def canned_address_verification_works?
        request = "%3CCarrierPickupAvailabilityRequest%20USERID=%22#{URI.encode(@options[:login])}%22%3E%20%0A%3CFirmName%3EABC%20Corp.%3C/FirmName%3E%20%0A%3CSuiteOrApt%3ESuite%20777%3C/SuiteOrApt%3E%20%0A%3CAddress2%3E1390%20Market%20Street%3C/Address2%3E%20%0A%3CUrbanization%3E%3C/Urbanization%3E%20%0A%3CCity%3EHouston%3C/City%3E%20%0A%3CState%3ETX%3C/State%3E%20%0A%3CZIP5%3E77058%3C/ZIP5%3E%20%0A%3CZIP4%3E1234%3C/ZIP4%3E%20%0A%3C/CarrierPickupAvailabilityRequest%3E%0A"
        # expected_hash = {"CarrierPickupAvailabilityResponse"=>{"City"=>"HOUSTON", "Address2"=>"1390 Market Street", "FirmName"=>"ABC Corp.", "State"=>"TX", "Date"=>"3/1/2004", "DayOfWeek"=>"Monday", "Urbanization"=>nil, "ZIP4"=>"1234", "ZIP5"=>"77058", "CarrierRoute"=>"C", "SuiteOrApt"=>"Suite 777"}}
        xml = REXML::Document.new(commit(:test, request, true))
        xml.get_text('/CarrierPickupAvailabilityResponse/City').to_s == 'HOUSTON' &&
        xml.get_text('/CarrierPickupAvailabilityResponse/Address2').to_s == '1390 Market Street'
      end

      # options[:service] --    One of [:first_class, :priority, :express, :bpm, :parcel,
      #                          :media, :library, :all]. defaults to :all.
      # options[:container] --  One of [:envelope, :box]. defaults to neither (this field has
      #                          special meaning in the USPS API).
      # options[:books] --      Either true or false. Packages of books or other printed matter
      #                          have a lower weight limit to be considered machinable.
      # package.options[:machinable] -- Either true or false. Overrides the detection of
      #                                  "machinability" entirely.
      def build_us_rate_request(packages, origin_zip, destination_zip, options={})
        packages = Array(packages)

        xml_request = Nokogiri::XML::Builder.new do
          RateV3Request(:USERID => options[:login]) {
            packages.each_with_index do |p, id|
              Package(:ID => id) {
                Service US_SERVICES[options[:service] || :all]
                ZipOrigination strip_zip(origin_zip)
                ZipDestination strip_zip(destination_zip)
                Pounds '0'
                Ounces "%0.1f" % [p.ounces, 1].max
                if p.options[:container] && [nil,:all,:express,:priority].include?(p.service)
                  Container CONTAINERS[p.options[:container]]
                end
                Size USPS.size_code_for(p)
                Width p.inches(:width)
                Length p.inches(:length)
                Height p.inches(:height)
                Girth p.inches(:girth)
                is_machinable = if p.options.has_key?(:machinable)
                  p.options[:machinable] ? true : false
                else
                  USPS.package_machinable?(p)
                end
                Machinable is_machinable.to_s.upcase
              }
            end
          }
        end
        xml_request.to_xml
      end

      # important difference with international rate requests:
      # * services are not given in the request
      # * package sizes are not given in the request
      # * services are returned in the response along with restrictions of size
      # * the size restrictions are returned AS AN ENGLISH SENTENCE (!?)
      #
      # 
      # package.options[:mail_type] -- one of [:package, :postcard, :matter_for_the_blind, :envelope].
      #                                 Defaults to :package.
      def build_world_rate_request(packages, destination_country, options = {})
        country = COUNTRY_NAME_CONVERSIONS[destination_country.code(:alpha2).first.value] || destination_country.name
        xml_request = Nokogiri::XML::Builder.new do
          IntlRateRequest(:USERID => options[:login]) {
            packages.each_with_index do |p, id|
              Package(:ID => id) {
                Pounds '0'
                Ounces ([p.ounces,1].max.ceil) #takes an integer for some reason, must be rounded UP
                MailType MAIL_TYPES[p.options[:mail_type]] || 'Package'
                if p.value && p.currency == 'USD'
                  ValueOfContents (p.value / 100.0)
                end
                Country country
              }
            end
          }
        end
        xml_request.to_xml
      end

      def parse_rate_response(origin, destination, packages, response, options={})
        rate_estimates = []
        message = ''

        xml = Nokogiri::XML::parse(response)

        case xml.root.name
          when 'Error' then
            message = xml.root.search('Description').text
          when 'RateV3Response' then
            rate_estimates = domestic_rates(:xml => xml, :origin => origin, :destination => destination, :packages => packages)
          when 'IntlRateResponse' then
            rate_estimates = international_rates(:xml => xml, :origin => origin, :destination => destination, :packages => packages)
          else
            message = "Unknown root node in XML response: '#{xml.root.name}'"
        end

        success = !rate_estimates.blank?
        RateResponse.new(success, message, {}, :rates => rate_estimates, :xml => response, :request => last_request)
      end

      def domestic_rates(opts = {})
        rate_estimates = []

        opts[:xml].root.search('Package').each do |package|
          package_id = package.attribute('ID').value.to_i
          package.search('Postage').each do |method|
            method_name = service_name(method.search('MailService').text)
            rate = rate_estimates.detect{|rate| rate.service_name.eql?(method_name)}
            if rate.blank?
              rate = RateEstimate.new(opts[:origin], opts[:destination], @@name, method_name,
                :package_rates => [],
                :service_code => method.attribute('CLASSID').value,
                :currency => 'USD')
              rate.add(opts[:packages][package_id], method.search('Rate').text)
              rate_estimates << rate
            else
              rate.add(opts[:packages][package_id], method.search('Rate').text)
            end
          end
        end
        rate_estimates.reject! {|e| e.package_count != opts[:packages].length}
        rate_estimates.sort_by(&:total_price)
      end

      def international_rates(opts = {})
        rate_estimates = []

        opts[:xml].root.search('Package').each do |package|
          package_id = package.attribute('ID').value.to_i
          package.search('Service').each do |method|
            next if !valid_package_for_service?(opts[:packages][package_id], method)

            method_name = service_name(method.search('SvcDescription').text)
            rate = rate_estimates.detect{|rate| rate.service_name.eql?(method_name)}
            if rate.blank?
              rate = RateEstimate.new(opts[:origin], opts[:destination], @@name, method_name,
                :package_rates => [],
                :service_code => method.attribute('ID').value,
                :currency => 'USD')
              rate.add(opts[:packages][package_id], method.search('Postage').text)
              rate_estimates << rate
            else
              rate.add(opts[:packages][package_id], method.search('Postage').text)
            end
          end
        end
        rate_estimates.reject! {|e| e.package_count != opts[:packages].length}
        rate_estimates.sort_by(&:total_price)
      end

      # Note: only filters International packages
      def valid_package_for_service?(package, method_node)
        max_weight = method_node.search('MaxWeight').text.to_f
        return true if max_weight <= 0.0
        name = method_node.search('SvcDescription').text
        dimension_text = method_node.search('MaxDimensions').text

        parse_dimensions(name, dimension_text, max_weight).each do |dimension|
          return true if package_valid_for_max_dimensions(package, dimension)
        end
        false
      end

      def parse_dimensions(method_name, dimension_text, max_weight)
        method_name = method_name.downcase

        # flat rate dimensions from
        #  * http://www.usps.com/prices/first-class-mail-prices.htm
        #  * http://www.usps.com/prices/express-mail-international-prices.htm
        #  * http://www.usps.com/prices/priority-mail-international-prices.htm
        case method_name
          when /small.flat.rate.box/ then
            return [{:weight => max_weight, :length => 8.625, :width => 5.375, :height => 1.625}]
          when /medium.flat.rate.box/ then
            return [{:weight => max_weight, :length => 11.0, :width => 8.5, :height => 5.5},
              {:weight => max_weight, :length => 13.625, :width => 11.875, :height => 3.375}]
          when /flat.rate.box/ then
            return [{:weight => max_weight, :length => 12.0, :width => 12.0, :height => 5.5}]
          when /large.envelope/ then
            return [{:weight => max_weight, :length => 15.0, :width => 12.0, :height => 0.75}]
          when /flat.rate.envelope/ then
            return [{:weight => max_weight, :length => 12.5, :width => 9.5, :height => 0.75}]
        end

        # Some sample english that this is required to parse:
        #
        # 'Max. length 46", width 35", height 46" and max. length plus girth 108"'
        # 'Max. length 24", Max. length, height, depth combined 36"'
        #
        sentence = CGI.unescapeHTML(dimension_text)
        tokens = sentence.downcase.split(/[^\d]*"/).reject {|t| t.empty?}
        max_dimensions = {:weight => max_weight}
        single_axis_values = []
        tokens.each do |token|
          axis_sum = [/length/,/width/,/height/,/depth/].sum {|regex| (token =~ regex) ? 1 : 0}
          unless axis_sum == 0
            value = token[/\d+$/].to_f 
            if axis_sum == 3
              max_dimensions[:length_plus_width_plus_height] = value
            elsif token =~ /girth/ and axis_sum == 1
              max_dimensions[:length_plus_girth] = value
            else
              single_axis_values << value
            end
          end
        end
        single_axis_values.sort!.reverse!
        [:length, :width, :height].each_with_index do |axis,i|
          max_dimensions[axis] = single_axis_values[i] if single_axis_values[i]
        end
        [max_dimensions]
      end

      def package_valid_for_max_dimensions(package, dimensions)
        valid = ((not ([:length,:width,:height].map {|dim| dimensions[dim].nil? || dimensions[dim].to_f >= package.inches(dim).to_f}.include?(false))) and
                (dimensions[:weight].nil? || dimensions[:weight] >= package.pounds) and
                (dimensions[:length_plus_girth].nil? or
                    dimensions[:length_plus_girth].to_f >=
                    package.inches(:length) + package.inches(:girth)) and
                (dimensions[:length_plus_width_plus_height].nil? or
                    dimensions[:length_plus_width_plus_height].to_f >=
                    package.inches(:length) + package.inches(:width) + package.inches(:height)))

        return valid
      end

      def commit(action, request, test = false)
        ssl_get(request_url(action, request, test))
      end

      def request_url(action, request, test)
        scheme = USE_SSL[action] ? 'https://' : 'http://'
        host = test ? TEST_DOMAINS[USE_SSL[action]] : LIVE_DOMAIN
        resource = test ? TEST_RESOURCE : LIVE_RESOURCE
        "#{scheme}#{host}/#{resource}?API=#{API_CODES[action]}&XML=#{request}"
      end

      def strip_zip(zip)
        zip.to_s.scan(/\d{5}/).first || zip
      end

      private

      def service_name(name)
        "#{@@name} #{name}"
      end

    end
  end
end
