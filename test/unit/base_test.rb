require File.dirname(__FILE__) + '/../test_helper'

class BaseTest < Test::Unit::TestCase
  include ActiveMerchant::Shipping

  def test_get_fedex
    assert_equal FedEx, Base.carrier('fedex')
    assert_equal FedEx, Base.carrier('FEDEX')
    assert_equal FedEx, Base.carrier(:fedex)
  end

  def test_get_shipwire
    assert_equal Shipwire, Base.carrier('shipwire')
    assert_equal Shipwire, Base.carrier('SHIPWIRE')
    assert_equal Shipwire, Base.carrier(:shipwire)
  end

  def test_get_ups
    assert_equal UPS, Base.carrier('ups')
    assert_equal UPS, Base.carrier('UPS')
    assert_equal UPS, Base.carrier(:ups)
  end

  def test_get_usps_by_string
    assert_equal USPS, Base.carrier('usps')
    assert_equal USPS, Base.carrier('USPS')
  end

  def test_get_usps_by_name
    assert_equal USPS, Base.carrier(:usps)
  end

  def test_get_unknown_carrier
    assert_raise(NameError){ Base.carrier(:polar_north) }
  end
end
