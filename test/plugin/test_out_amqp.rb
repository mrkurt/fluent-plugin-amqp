# encoding: utf-8

require_relative '../helper'
require 'fluent/test'
require 'fluent/plugin/out_amqp'

# Protection against optional dependency - Ruby 1.9 can't
# include bunny-mock as its not supported
begin
  require 'bunny-mock'
rescue LoadError
  # Bunny-Mock requires Ruby 2+ and we're probably running on
  # 1.9 - so the require explodes
end

class AMPQOutputTest < Test::Unit::TestCase

  attr_reader :driver

  def setup
    Fluent::Test.setup
  end

def get_plugin
  omit("BunnyMock is not avaliable") unless Object.const_defined?("BunnyMock")

  @driver = create_driver(CONFIG)
  plugin = @driver.instance
  plugin.connection = BunnyMock.new

  # Start the driver and wait while it initialises the threads etc
  plugin.start
  10.times { sleep 0.05 }
  return plugin
end

  CONFIG = %[
    type amqp
    format json
    host amqp.example.com
    port 5672
    vhost /
    user guest
    pass guest
    exchange my_exchange
    exchange_type fanout
    tag_key true
  ]

  TLS_CONFIG = CONFIG + %[
    tls true
    tls_key "/etc/fluent/ssl/client.key.pem"
    tls_cert "/etc/fluent/ssl/client.crt.pem"
    tls_ca_certificates ["/etc/fluent/ssl/server.cacrt.pem", "/another/ca/cert.file"]
    tls_verify_peer true
  ]

  def create_driver(conf, tag='test')
    Fluent::Test::BufferedOutputTestDriver.new(Fluent::AMQPOutput,tag).configure(conf)
  end

  sub_test_case 'configuration' do
    test 'basic configuration' do
      configs = {'basic' => CONFIG}
      configs.merge!('tls' => TLS_CONFIG)

      configs.each_pair { |k, v|
        d = create_driver(v)
        assert_equal "amqp.example.com", d.instance.host
        assert_equal 5672, d.instance.port
        assert_equal "guest", d.instance.user
        assert_equal "/", d.instance.vhost
      }
    end

    test 'array of hosts' do
      conf = CONFIG + %[
        type amqp
        format json
        hosts ["bob","fred"]
        ]

      d = create_driver(conf)
      assert_equal ["bob", "fred"], d.instance.hosts
      assert_equal 5672, d.instance.port
      assert_equal "guest", d.instance.user
      assert_equal "/", d.instance.vhost
    end

    test 'invalid tls configuration' do
      assert_raise_message(/'tls_key' and 'tls_cert' must be all specified if tls is enabled./) do
        create_driver(CONFIG + %[tls true])
      end
    end

    test 'invalid host configuration' do
      assert_raise_message(/'host' or 'hosts' must be specified./) do
        create_driver(%[
          type amqp
          format json
          tag_key true
          ])
      end
    end

    test 'invalid tag / tag_key configuration' do
      assert_raise_message(/Either 'key' or 'tag_key' must be set./) do
        create_driver(%[
          type amqp
          format json
          host anywhere.example.com
          ])
      end
    end
  end

  sub_test_case 'connection handling' do

    test 'Exchange is created and bound to' do

      plugin = get_plugin()

      # Should have created the 'logs' queue
      assert_equal true, plugin.connection.exchange_exists?('my_exchange')
      pend("Unable to check binding state - cant reach channel instance") {
        chnl = plugin.somehow_get_channel
        asset_equal true, chnl.bound_to?('my_exchange')
      }
    end

  end

  sub_test_case 'message_writing' do


    test 'A simple object can be written to the broker' do
# Testing these two bits;
#      data = JSON.dump( data ) unless data.is_a?( String )
#      @exch.publish(data, :key => routing_key( tag ), :persistent => @persistent, :headers => headers( tag, time ))

      plugin = get_plugin()

      # Should have created the 'logs' queue
      assert_equal true, plugin.connection.exchange_exists?('my_exchange')

      # bind a testing queue to the exchange
      queue = plugin.channel.queue 'my.test.queue'
      queue.bind plugin.exch, routing_key: 'test'
      # queue.test is now bound to the configured exchange

      # Emit an event through the plugins driver
      @driver.emit( 'This is a simple string')
      @driver.run

      # Validate the message was delivered
      assert_equal 1, queue.message_count
      assert_equal 'This is a simple string', queue.pop[:message]

    end

    test 'An object can be written to the broker and is converted to json' do
  # Testing these two bits;
  #      data = JSON.dump( data ) unless data.is_a?( String )
  #      @exch.publish(data, :key => routing_key( tag ), :persistent => @persistent, :headers => headers( tag, time ))

      plugin = get_plugin()

      # Should have created the 'logs' queue
      assert_equal true, plugin.connection.exchange_exists?('my_exchange')

      # bind a testing queue to the exchange
      queue = plugin.channel.queue 'my.test.queue'
      queue.bind plugin.exch, routing_key: 'test'
      # queue.test is now bound to the configured exchange

      # Emit an event through the plugins driver
      object = { message: 'This is an event', nested: { type: 'hash', value: 'banana'} }
      @driver.emit( object )
      @driver.run

      # Validate the message was delivered
      assert_equal 1, queue.message_count
      assert_equal JSON.dump(object) , queue.pop[:message]

    end


    test 'Test UTF8 unicode and emoji strings do not crash the plugin' do
  # Testing these two bits;
  #      data = JSON.dump( data ) unless data.is_a?( String )
  #      @exch.publish(data, :key => routing_key( tag ), :persistent => @persistent, :headers => headers( tag, time ))

      plugin = get_plugin()

      # Should have created the 'logs' queue
      assert_equal true, plugin.connection.exchange_exists?('my_exchange')

      # bind a testing queue to the exchange
      queue = plugin.channel.queue 'my.test.queue'
      queue.bind plugin.exch, routing_key: 'test'
      # queue.test is now bound to the configured exchange

      complex_string_msg = { message: '日 🕵 iPhone\xAE \u{1f60e}' }
      # Emit an event through the plugins driver
      @driver.emit( complex_string_msg )
      @driver.run

      # Validate the message was _not_ delivered
      assert_equal 1, queue.message_count
      assert_equal JSON.dump(complex_string_msg) , queue.pop[:message]

    end

  end
end
