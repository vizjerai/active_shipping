# FedEx module by Jimmy Baker
# http://github.com/jimmyebaker

module ActiveMerchant
  module Shipping

    # :key is your developer API key
    # :password is your API password
    # :account is your FedEx account number
    # :login is your meter number
    class FedEx < Carrier
      self.retry_safe = true

      cattr_reader :name
      @@name = "FedEx"

      TEST_URL = 'https://gatewaybeta.fedex.com:443/xml'
      LIVE_URL = 'https://gateway.fedex.com:443/xml'

      CarrierCodes = {
        "fedex_ground" => "FDXG",
        "fedex_express" => "FDXE"
      }

      ServiceTypes = {
        "PRIORITY_OVERNIGHT" => "FedEx Priority Overnight",
        "PRIORITY_OVERNIGHT_SATURDAY_DELIVERY" => "FedEx Priority Overnight Saturday Delivery",
        "FEDEX_2_DAY" => "FedEx 2 Day",
        "FEDEX_2_DAY_SATURDAY_DELIVERY" => "FedEx 2 Day Saturday Delivery",
        "STANDARD_OVERNIGHT" => "FedEx Standard Overnight",
        "FIRST_OVERNIGHT" => "FedEx First Overnight",
        "FEDEX_EXPRESS_SAVER" => "FedEx Express Saver",
        "FEDEX_1_DAY_FREIGHT" => "FedEx 1 Day Freight",
        "FEDEX_1_DAY_FREIGHT_SATURDAY_DELIVERY" => "FedEx 1 Day Freight Saturday Delivery",
        "FEDEX_2_DAY_FREIGHT" => "FedEx 2 Day Freight",
        "FEDEX_2_DAY_FREIGHT_SATURDAY_DELIVERY" => "FedEx 2 Day Freight Saturday Delivery",
        "FEDEX_3_DAY_FREIGHT" => "FedEx 3 Day Freight",
        "FEDEX_3_DAY_FREIGHT_SATURDAY_DELIVERY" => "FedEx 3 Day Freight Saturday Delivery",
        "INTERNATIONAL_PRIORITY" => "FedEx International Priority",
        "INTERNATIONAL_PRIORITY_SATURDAY_DELIVERY" => "FedEx International Priority Saturday Delivery",
        "INTERNATIONAL_ECONOMY" => "FedEx International Economy",
        "INTERNATIONAL_FIRST" => "FedEx International First",
        "INTERNATIONAL_PRIORITY_FREIGHT" => "FedEx International Priority Freight",
        "INTERNATIONAL_ECONOMY_FREIGHT" => "FedEx International Economy Freight",
        "GROUND_HOME_DELIVERY" => "FedEx Ground Home Delivery",
        "FEDEX_GROUND" => "FedEx Ground",
        "INTERNATIONAL_GROUND" => "FedEx International Ground"
      }

      PackageTypes = {
        "fedex_envelope" => "FEDEX_ENVELOPE",
        "fedex_pak" => "FEDEX_PAK",
        "fedex_box" => "FEDEX_BOX",
        "fedex_tube" => "FEDEX_TUBE",
        "fedex_10_kg_box" => "FEDEX_10KG_BOX",
        "fedex_25_kg_box" => "FEDEX_25KG_BOX",
        "your_packaging" => "YOUR_PACKAGING"
      }

      DropoffTypes = {
        'regular_pickup' => 'REGULAR_PICKUP',
        'request_courier' => 'REQUEST_COURIER',
        'dropbox' => 'DROP_BOX',
        'business_service_center' => 'BUSINESS_SERVICE_CENTER',
        'station' => 'STATION'
      }

      PaymentTypes = {
        'sender' => 'SENDER',
        'recipient' => 'RECIPIENT',
        'third_party' => 'THIRDPARTY',
        'collect' => 'COLLECT'
      }

      PackageIdentifierTypes = {
        'tracking_number' => 'TRACKING_NUMBER_OR_DOORTAG',
        'door_tag' => 'TRACKING_NUMBER_OR_DOORTAG',
        'rma' => 'RMA',
        'ground_shipment_id' => 'GROUND_SHIPMENT_ID',
        'ground_invoice_number' => 'GROUND_INVOICE_NUMBER',
        'ground_customer_reference' => 'GROUND_CUSTOMER_REFERENCE',
        'ground_po' => 'GROUND_PO',
        'express_reference' => 'EXPRESS_REFERENCE',
        'express_mps_master' => 'EXPRESS_MPS_MASTER'
      }

      def requirements
        [:key, :password, :account, :login]
      end

      def find_rates(origin, destination, packages, options = {})
        options = @options.update(options)
        packages = Array(packages)

        rate_request = build_rate_request(origin, destination, packages, options)

        response = commit(save_request(rate_request), (options[:test] || false))

        parse_rate_response(origin, destination, packages, response, options)
      end

      def find_tracking_info(tracking_number, options={})
        options = @options.update(options)

        tracking_request = build_tracking_request(tracking_number, options)
        response = commit(save_request(tracking_request), (options[:test] || false)).gsub(/<(\/)?.*?\:(.*?)>/, '<\1\2>')
        parse_tracking_response(response, options)
      end

      protected

      def build_rate_request(origin, destination, packages, options={})
        imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))

        xml_request = Nokogiri::XML::Builder.new do
          RateRequest(:xmlns => 'http://fedex.com/ws/rate/v6') {
            # Header Information
            WebAuthenticationDetail {
              UserCredential {
                Key options[:key]
                Password options[:password]
              }
            }
            ClientDetail {
              AccountNumber options[:account]
              MeterNumber options[:login]
            }
            TransactionDetail {
              CustomerTransactionId 'ActiveShipping'
            }

            # Version
            Version {
              ServiceId 'crs'
              Major '6'
              Intermediate '0'
              Minor '0'
            }

            # Returns Delivery Dates
            ReturnTransitAndCommit true
            # Returns saturday delivery shipping options when available
            VariableOptions 'SATURDAY_DELIVERY'

            RequestedShipment {
              ShipTimestamp Time.now.xmlschema
              DropoffType options[:dropoff_type] || 'REGULAR_PICKUP'
              PackagingType options[:packaging_type] || 'YOUR_PACKAGING'

              Shipper {
                location = (options[:shipper] || origin)
                Address {
                  PostalCode location.postal_code
                  CountryCode location.country_code(:alpha2)
                  case location.address_type
                    when 'commercial' then Residential false
                    when 'residential' then Residential true
                  end
                }
              }
              Recipient {
                location = destination
                Address {
                  PostalCode location.postal_code
                  CountryCode location.country_code(:alpha2)
                  case location.address_type
                    when 'commercial' then Residential false
                    when 'residential' then Residential true
                  end
                }
              }
              if options[:shipper] and options[:shipper] != origin
                Origin {
                  location = origin
                  Address {
                    PostalCode location.postal_code
                    CountryCode location.country_code(:alpha2)
                    case location.address_type
                      when 'commercial' then Residential false
                      when 'residential' then Residential true
                    end
                  }
                }
              end

              #package
              RateRequestTypes 'ACCOUNT'
              PackageCount packages.size

              packages.each do |pkg|
                RequestedPackages {
                  Weight {
                    Units imperial ? 'LB' : 'KG'
                    Value [((imperial ? pkg.lbs : pkg.kgs).to_f*1000).round/1000.0, 0.1].max
                  }
                  Dimensions {
                    if imperial
                      Length (((pkg.inches(:length).to_f * 1000.0).round / 1000.0).ceil) # 3 decimals
                      Width (((pkg.inches(:width).to_f * 1000.0).round / 1000.0).ceil) # 3 decimals
                      Height (((pkg.inches(:height).to_f * 1000.0).round / 1000.0).ceil) # 3 decimals
                      Units 'IN'
                    else
                      Length (((pkg.cm(:length).to_f * 1000.0).round / 1000.0).ceil) # 3 decimals
                      Width (((pkg.cm(:width).to_f * 1000.0).round / 1000.0).ceil) # 3 decimals
                      Height (((pkg.cm(:height).to_f * 1000.0).round / 1000.0).ceil) # 3 decimals
                      Units 'CM'
                    end
                  }
                }
              end
            }
          }
        end
        xml_request.to_xml
      end

      def build_tracking_request(tracking_number, options={})
        xml_request = XmlNode.new('TrackRequest', 'xmlns' => 'http://fedex.com/ws/track/v3') do |root_node|
          root_node << build_request_header

          # Version
          root_node << XmlNode.new('Version') do |version_node|
            version_node << XmlNode.new('ServiceId', 'trck')
            version_node << XmlNode.new('Major', '3')
            version_node << XmlNode.new('Intermediate', '0')
            version_node << XmlNode.new('Minor', '0')
          end

          root_node << XmlNode.new('PackageIdentifier') do |package_node|
            package_node << XmlNode.new('Value', tracking_number)
            package_node << XmlNode.new('Type', PackageIdentifierTypes[options['package_identifier_type'] || 'tracking_number'])
          end

          root_node << XmlNode.new('ShipDateRangeBegin', options['ship_date_range_begin']) if options['ship_date_range_begin']
          root_node << XmlNode.new('ShipDateRangeEnd', options['ship_date_range_end']) if options['ship_date_range_end']
          root_node << XmlNode.new('IncludeDetailedScans', 1)
        end
        xml_request.to_s
      end

      def build_request_header
        web_authentication_detail = XmlNode.new('WebAuthenticationDetail') do |wad|
          wad << XmlNode.new('UserCredential') do |uc|
            uc << XmlNode.new('Key', @options[:key])
            uc << XmlNode.new('Password', @options[:password])
          end
        end

        client_detail = XmlNode.new('ClientDetail') do |cd|
          cd << XmlNode.new('AccountNumber', @options[:account])
          cd << XmlNode.new('MeterNumber', @options[:login])
        end

        trasaction_detail = XmlNode.new('TransactionDetail') do |td|
          td << XmlNode.new('CustomerTransactionId', 'ActiveShipping') # TODO: Need to do something better with this..
        end

        [web_authentication_detail, client_detail, trasaction_detail]
      end

      def parse_rate_response(origin, destination, packages, response, options)
        rate_estimates = []
        success = false
        message = ''

        xml = Nokogiri::XML::parse(response).remove_namespaces!()

        xml.root.children.each do |node|
          if node.name.eql?('Notifications')
            success = %w{SUCCESS WARNING NOTE}.include? node.xpath('Severity').text
            message = "#{node.xpath('Severity').text} - #{node.xpath('Code').text}: #{node.xpath('Message').text}"
          elsif node.name.eql?('RateReplyDetails')
            service_code = node.xpath('ServiceType').text
            service_type = service_code
            if node.xpath('AppliedOptions').text.eql?('SATURDAY_DELIVERY')
              service_type += "_SATURDAY_DELIVERY"
            end
            rate_type = node.xpath('ActualRateType').text
            rate_estimates << RateEstimate.new(origin, destination, @@name,
              ServiceTypes[service_type],
              :service_code => service_code,
              :total_price => node.xpath('RatedShipmentDetails/ShipmentRateDetail[RateType="' + rate_type + '"]/TotalNetCharge/Amount').text.to_f,
              :currency => node.xpath('RatedShipmentDetails/ShipmentRateDetail[RateType="' + rate_type + '"]/TotalNetCharge/Currency').text,
              :packages => packages,
              :delivery_date => node.xpath('DeliveryTimestamp').text)
          end
        end

        if rate_estimates.empty?
          success = false
          message = "No shipping rates could be found for the destination address" if message.blank?
        end

        RateResponse.new(success, message, {}, :rates => rate_estimates, :xml => response, :request => last_request, :log_xml => options[:log_xml])
      end

      def parse_tracking_response(response, options)
        xml = REXML::Document.new(response)
        root_node = xml.elements['TrackReply']

        success = response_success?(xml)
        message = response_message(xml)

        if success
          tracking_number, origin, destination = nil
          shipment_events = []

          tracking_details = root_node.elements['TrackDetails']
          tracking_number = tracking_details.get_text('TrackingNumber').to_s

          destination_node = tracking_details.elements['DestinationAddress']
          destination = Location.new(
                :country =>     destination_node.get_text('CountryCode').to_s,
                :province =>    destination_node.get_text('StateOrProvinceCode').to_s,
                :city =>        destination_node.get_text('City').to_s
              )

          tracking_details.elements.each('Events') do |event|
            location = Location.new(
              :city => event.elements['Address'].get_text('City').to_s,
              :state => event.elements['Address'].get_text('StateOrProvinceCode').to_s,
              :postal_code => event.elements['Address'].get_text('PostalCode').to_s,
              :country => event.elements['Address'].get_text('CountryCode').to_s)
            description = event.get_text('EventDescription').to_s

            # for now, just assume UTC, even though it probably isn't
            time = Time.parse("#{event.get_text('Timestamp').to_s}")
            zoneless_time = Time.utc(time.year, time.month, time.mday, time.hour, time.min, time.sec)
            
            shipment_events << ShipmentEvent.new(description, zoneless_time, location)
          end
          shipment_events = shipment_events.sort_by(&:time)
        end

        TrackingResponse.new(success, message, Hash.from_xml(response),
          :xml => response,
          :request => last_request,
          :shipment_events => shipment_events,
          :destination => destination,
          :tracking_number => tracking_number
        )
      end

      def response_status_node(document)
        document.elements['/*/Notifications/']
      end

      def response_success?(document)
        %w{SUCCESS WARNING NOTE}.include? response_status_node(document).get_text('Severity').to_s
      end

      def response_message(document)
        response_node = response_status_node(document)
        "#{response_status_node(document).get_text('Severity').to_s} - #{response_node.get_text('Code').to_s}: #{response_node.get_text('Message').to_s}"
      end

      def commit(request, test = false)
        ssl_post(test ? TEST_URL : LIVE_URL, request.gsub("\n",''))        
      end
    end
  end
end
