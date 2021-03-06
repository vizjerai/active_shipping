require File.dirname(__FILE__) + '/../../test_helper'

class USPSTest < Test::Unit::TestCase
  def setup
    @packages  = TestFixtures.packages
    @locations = TestFixtures.locations
    @carrier   = USPS.new(:login => '12345')
    @fixtures = {
      :rate_request => {
        :domestic => xml_fixture('usps/new_york_to_beverly_hills_rate_request'),
        :international => xml_fixture('usps/beverly_hills_to_ottawa_rate_request')
      },
      :rate_response => {
        :domestic => xml_fixture('usps/new_york_to_beverly_hills_rate_response'),
        :international => xml_fixture('usps/beverly_hills_to_ottawa_rate_response')}}
  end

  def test_initialize_options_requirements
    assert_raises ArgumentError do USPS.new end
    assert_nothing_raised ArgumentError do USPS.new(:login => '999999999') end
  end

  def test_domestic_building_request_and_parse_response
    @carrier.expects(:build_us_rate_request).returns(@fixtures[:rate_request][:domestic])
    @carrier.expects(:commit).returns(@fixtures[:rate_response][:domestic])

    response = @carrier.find_rates(
      @locations[:new_york],
      @locations[:beverly_hills],
      @packages.values_at(:book,:wii),
      :test => true)

    assert_equal @fixtures[:rate_response][:domestic], response.xml

    assert_not_equal [], response.rates
    assert_equal ["1", "2", "3", "4", "5", "6", "7", "13", "16", "17", "22", "27", "28"], response.rates.map(&:service_code).sort {|a,b| a.to_i <=> b.to_i}
    assert_equal ["USPS Bound Printed Matter", "USPS Express Mail", "USPS Express Mail Flat Rate Envelope", "USPS Express Mail Flat Rate Envelope Hold For Pickup", "USPS Express Mail Hold For Pickup", "USPS Library Mail", "USPS Media Mail", "USPS Parcel Post", "USPS Priority Mail", "USPS Priority Mail Flat Rate Envelope", "USPS Priority Mail Large Flat Rate Box", "USPS Priority Mail Medium Flat Rate Box", "USPS Priority Mail Small Flat Rate Box"], response.rates.map(&:service_name).sort
    assert_equal [709, 749, 953, 990, 990, 1993, 2070, 2790, 2970, 3500, 3500, 7680, 7680], response.rates.map(&:total_price)
  end

  def test_international_building_request_and_parse_response
    @carrier.expects(:build_world_rate_request).returns(@fixtures[:rate_request][:international])
    @carrier.expects(:commit).returns(@fixtures[:rate_response][:international])

    response = @carrier.find_rates(
      @locations[:beverly_hills],
      @locations[:ottawa],
      @packages.values_at(:book, :wii),
      :test => true)

    assert_equal @fixtures[:rate_response][:international], response.xml

    assert_not_equal [],response.rates
    assert_equal ["1", "2", "4", "6", "7", "12"], response.rates.map(&:service_code).sort {|a,b| a.to_i <=> b.to_i}
    assert_equal ["USPS Express Mail International", "USPS Global Express Guaranteed (GXG)", "USPS Global Express Guaranteed Non-Document Non-Rectangular", "USPS Global Express Guaranteed Non-Document Rectangular", "USPS Priority Mail International", "USPS USPS GXG Envelopes"], response.rates.map(&:service_name).sort
    assert_equal [5025, 8375, 13025, 13025, 13025, 13025], response.rates.map(&:total_price)
  end

  def test_size_code_for
    assert_equal 'REGULAR', USPS.size_code_for(Package.new(1, [80,1,1], :units => :imperial))
    assert_equal 'LARGE', USPS.size_code_for(Package.new(1, [81,1,1], :units => :imperial))
    assert_equal 'OVERSIZE', USPS.size_code_for(Package.new(1, [105,1,1], :units => :imperial))
  end

  def test_maximum_weight
    assert Package.new(70 * 16, [5,5,5], :units => :imperial).mass == @carrier.maximum_weight
    assert Package.new((70 * 16) + 0.01, [5,5,5], :units => :imperial).mass > @carrier.maximum_weight
    assert Package.new((70 * 16) - 0.01, [5,5,5], :units => :imperial).mass < @carrier.maximum_weight
  end
=begin
  def test_parse_max_dimension_sentences
    limits = {
      "Max. length 46\", width 35\", height 46\" and max. length plus girth 108\"" =>
        [{:length => 46.0, :width => 46.0, :height => 35.0, :length_plus_girth => 108.0}],
      "Max.length 42\", max. length plus girth 79\"" =>
        [{:length => 42.0, :length_plus_girth => 79.0}],
      "9 1/2\" X 12 1/2\"" =>
        [{:length => 12.5, :width => 9.5, :height => 0.75}, "Flat Rate Envelope"],
      "Maximum length and girth combined 108\"" =>
        [{:length_plus_girth => 108.0}],
      "USPS-supplied Priority Mail flat-rate envelope 9 1/2\" x 12 1/2.\" Maximum weight 4 pounds." =>
        [{:length => 12.5, :width => 9.5, :height => 0.75}, "Flat Rate Envelope"],
      "Max. length 24\", Max. length, height, depth combined 36\"" =>
        [{:length => 24.0, :length_plus_width_plus_height => 36.0}]
    }
    p = @packages[:book]
    limits.each do |sentence,hashes|
      dimensions = hashes[0].update(:weight => 50.0)
      service_node = build_service_node(
        :name => hashes[1],
        :max_weight => 50,
        :max_dimensions => sentence )
      @carrier.expects(:package_valid_for_max_dimensions).with(p, dimensions)
      @carrier.send(:package_valid_for_service, p, service_node)
    end
  
    service_node = build_service_node(
        :name => "flat-rate box",
        :max_weight => 50,
        :max_dimensions => "USPS-supplied Priority Mail flat-rate box. Maximum weight 20 pounds." )
    
    # should test against either kind of flat rate box:
    dimensions = [{:weight => 50.0, :length => 11.0, :width => 8.5, :height => 5.5}, # or...
      {:weight => 50.0, :length => 13.625, :width => 11.875, :height => 3.375}]
    @carrier.expects(:package_valid_for_max_dimensions).with(p, dimensions[0])
    @carrier.expects(:package_valid_for_max_dimensions).with(p, dimensions[1])
    @carrier.send(:package_valid_for_service, p, service_node)
    
  end
=end
  def test_package_valid_for_max_dimensions
    p = Package.new(70 * 16, [10,10,10], :units => :imperial)
    limits = {:weight => 70.0, :length => 10.0, :width => 10.0, :height => 10.0, :length_plus_girth => 50.0, :length_plus_width_plus_height => 30.0}
    assert_equal true, @carrier.send(:package_valid_for_max_dimensions, p, limits)
    
    limits.keys.each do |key|
      dimensions = {key => (limits[key] - 1)}
      assert_equal false, @carrier.send(:package_valid_for_max_dimensions, p, dimensions)
    end
  end

  def test_parse_dimensions
    dimensions = @carrier.send(:parse_dimensions, 'Priority Mail International Regular/Medium Flat-Rate Boxes', '', 20)
    assert_equal 20, dimensions[0][:weight]
    assert_equal 11.0, dimensions[0][:length]
    assert_equal 8.5, dimensions[0][:width]
    assert_equal 5.5, dimensions[0][:height]
    
    assert_equal 20, dimensions[1][:weight]
    assert_equal 13.625, dimensions[1][:length]
    assert_equal 11.875, dimensions[1][:width]
    assert_equal 3.375, dimensions[1][:height]

    dimensions = [
      {:method => 'Priority Mail International Small Flat-Rate Box', :text => '',
        :weight => 4, :length => 8.625, :width => 5.375, :height => 1.625},
      {:method => 'Priority Mail International Large Flat-Rate Box', :text => '',
        :weight => 20, :length => 12.0, :width => 12.0, :height => 5.5},
      {:method => 'Express Mail International (EMS) Flat-Rate Envelope', :text => '',
        :weight => 70, :length => 12.5, :width => 9.5, :height => 0.75},
      {:method => 'First Class Mail International Large Envelope', :text => '',
        :weight => 1, :length => 15.0, :width => 12.0, :height => 0.75},
      {:method => '', :text => 'Max. length 46", width 35", height 46" and max. length plus girth 108"',
        :weight => 35, :length => 46.0, :width => 46.0, :height => 35.0, :length_plus_girth => 108.0},
      {:method => '', :text => 'Maximum length and girth combined 108"',
        :weight => 45, :length_plus_girth => 108.0},
      {:method => '', :text => 'Maximum length and girth combined 108"',
        :weight => 10, :length_plus_girth => 108.0},
      {:method => '', :text => 'Max.length 42", max. length plus girth 79"',
        :weight => 55, :length => 42.0, :length_plus_girth => 79.0},
      {:method => '', :text => 'Max. length 24", Max. length, height, depth combined 36"',
        :weight => 5, :length => 24.0, :length_plus_width_plus_height => 36.0},
      {:method => '', :text => 'Max. length 24", max length, height and depth (thickness) combined 36"',
        :weight => 11, :length => 24.0, :length_plus_width_plus_height => 36.0}]

    dimensions.each do |dimension|
      results = @carrier.send(:parse_dimensions, dimension[:method], dimension[:text], dimension[:weight])
      assert_equal 1, results.length
      result = results.first
      assert_equal dimension[:weight], result[:weight]
      assert_equal dimension[:length], result[:length]
      assert_equal dimension[:width], result[:width]
      assert_equal dimension[:height], result[:height]
      assert_equal dimension[:length_plus_girth], result[:length_plus_girth]
      assert_equal dimension[:length_plus_width_plus_height], result[:length_plus_width_plus_height]
    end

  # Max. length 15", height 12 or more than 3/4" thick

  end
  
  def test_strip_9_digit_zip_codes
    request = URI.decode(@carrier.send(:build_us_rate_request, @packages[:book], "90210-1234", "123456789"))
    assert !(request =~ /\>90210-1234\</)
    assert request =~ /\>90210\</
    assert !(request =~ /\>123456789\</)
    assert request =~ /\>12345\</
  end
=begin
  def test_xml_logging_to_file
    mock_response = @fixtures[:rate_response][:international]
    @carrier.expects(:commit).times(2).returns(mock_response)
    @carrier.find_rates(
      @locations[:beverly_hills],
      @locations[:ottawa],
      @packages[:book],
      :test => true
    )
    @carrier.find_rates(
      @locations[:beverly_hills],
      @locations[:ottawa],
      @packages[:book],
      :test => true
    )
  end
=end
  private
  
  def build_service_node(options = {})
    XmlNode.new('Service') do |service_node|
      service_node << XmlNode.new('Pounds', options[:pounds] || "0")
      service_node << XmlNode.new('SvcCommitments', options[:svc_commitments] || "Varies")
      service_node << XmlNode.new('Country', options[:country] || "CANADA")
      service_node << XmlNode.new('ID', options[:id] || "3")
      service_node << XmlNode.new('MaxWeight', options[:max_weight] || "64")
      service_node << XmlNode.new('SvcDescription', options[:name] || "First-Class Mail International")
      service_node << XmlNode.new('MailType', options[:mail_type] || "Package")
      service_node << XmlNode.new('Postage', options[:postage] || "3.76")
      service_node << XmlNode.new('Ounces', options[:ounces] || "9")
      service_node << XmlNode.new('MaxDimensions', options[:max_dimensions] || 
          "Max. length 24\", Max. length, height, depth combined 36\"")
    end.to_xml_element
  end

end