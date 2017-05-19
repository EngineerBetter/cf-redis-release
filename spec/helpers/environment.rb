require 'prof/environment/cloud_foundry'

require 'support/redis_service_broker'
require 'support/redis_service_client_builder'

class FilteredStderr < StringIO
  def write value
    if value.include? "Object#timeout is deprecated"
      return
    end

    if value == "\n"
      return
    end

    STDERR.write value
  end
end

module Helpers
  module Environment
    fail "Must specify BOSH_MANIFEST environment variable" unless ENV.key?('BOSH_MANIFEST')

    def environment
      @environment ||= begin
        options = {
          bosh_manifest_path: ENV.fetch('BOSH_MANIFEST'),
          bosh_service_broker_job_name: 'cf-redis-broker'
        }
        options[:bosh_target]          = ENV['BOSH_TARGET']                 if ENV.key?('BOSH_TARGET')
        options[:bosh_username]        = ENV['BOSH_USERNAME']               if ENV.key?('BOSH_USERNAME')
        options[:bosh_password]        = ENV['BOSH_PASSWORD']               if ENV.key?('BOSH_PASSWORD')


        options[:ssh_gateway_host]        = ssh_gateway_host
        options[:ssh_gateway_private_key] = ENV['JUMPBOX_PRIVATE_KEY'] if ENV.key?('JUMPBOX_PRIVATE_KEY')
        options[:ssh_gateway_username]    = ENV['JUMPBOX_USERNAME'] if ENV.key?('JUMPBOX_USERNAME')
        options[:ssh_gateway_password]    = ENV['JUMPBOX_PASSWORD'] if ENV.key?('JUMPBOX_PASSWORD')

        options[:use_proxy]               = ENV['USE_PROXY'] == 'true'
        options[:bosh_target_is_public]   = ENV['BOSH_TARGET_IS_PUBLIC'] == 'true'
        options[:bosh_ca_cert]            = ENV['BOSH_CA_CERT'] if ENV.key?('BOSH_CA_CERT')
        Prof::Environment::CloudFoundry.new(options)
      end
    end

    def ssh_gateway_host
      host = ENV.fetch('JUMPBOX_HOST', ENV.fetch('BOSH_TARGET', nil))
      host = 'http://' + host unless host.start_with? 'http'
      URI.parse(host).host unless host.nil?
    end

    def redis_service_broker
      Support::RedisServiceBroker.new(service_broker)
    end

    def service_broker
      environment.service_broker
    end

    def bosh_manifest
      environment.bosh_manifest
    end

    def bosh_director
      environment.bosh_director
    end

    # net-ssh makes a deprecated call to `timeout`. We ignore these messages because they pollute logs.
    # After using the filtered stderr we ensure to reassign the original stderr
    # stream.
    def ssh_gateway
      gateway = environment.ssh_gateway
      def gateway.execute_on(*args, &block)
        begin
          original_stderr = $stderr
          $stderr = FilteredStderr.new
          super
        ensure
          $stderr = original_stderr
        end
      end

      def gateway.scp_to(*args, &block)
        begin
          original_stderr = $stderr
          $stderr = FilteredStderr.new
          super
        ensure
          $stderr = original_stderr
        end
      end

      gateway
    end

    def broker_host
      bosh_manifest.job('cf-redis-broker').static_ips.first
    end

    def node_hosts
      bosh_manifest.job('dedicated-node').static_ips
    end

    def broker_backend_port
      bosh_manifest.property('redis').fetch('broker').fetch('backend_port')
    end

    def agent_backend_port
      bosh_manifest.property('redis').fetch('agent').fetch('backend_port')
    end

    def service_client_builder(binding)
      Support::RedisServiceClientBuilder.new(
        ssh_gateway:    ssh_gateway,
        save_command:   bosh_manifest.property('redis.save_command'),
        config_command: bosh_manifest.property('redis.config_command')
      ).build(binding)
    end
  end
end
