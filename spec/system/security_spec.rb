require 'system_spec_helper'

require 'socket'
require 'timeout'

describe 'security' do
  describe 'the broker' do
    it 'uses latest version of nginx' do
      output = broker_ssh.exec!('/var/vcap/packages/cf-redis-nginx/sbin/nginx -v').strip
      expect(output).to eq('nginx version: nginx/1.8.0')
    end

    it 'does not listen publicly on the backend_port' do
      netstat_output = broker_ssh.exec!("netstat -l | grep #{broker_backend_port}")
      expect(netstat_output.lines.count).to eq(1)
      expect(netstat_output).to include("localhost:#{broker_backend_port}")
    end
  end

  describe 'the agents' do
    it 'uses latest version of nginx' do
      output = node_ssh.exec!('/var/vcap/packages/cf-redis-nginx/sbin/nginx -v').strip
      expect(output).to eql('nginx version: nginx/1.8.0')
    end

    it 'only supports HTTPS with restricted ciphers' do
      supported_ciphers = ["DHE-RSA-AES128-GCM-SHA256", "DHE-RSA-AES256-GCM-SHA384", "ECDHE-RSA-AES128-GCM-SHA256", "ECDHE-RSA-AES256-GCM-SHA384"]
      expect(get_allowed_ciphers).to contain_exactly(*supported_ciphers)
    end

    it 'does not listen publicly on the backend_port' do
      netstat_output = node_ssh.exec!("netstat -l | grep #{agent_backend_port}")
      expect(netstat_output.lines.count).to eq(1)
      expect(netstat_output).to include("localhost:#{agent_backend_port}")
    end
  end
end

def get_allowed_ciphers
  command = '
    #!/bin/bash

    SERVER=localhost:4443
    ciphers=$(openssl ciphers "ALL:eNULL" | sed -e "s/:/ /g")

    function test_cipher() {
      echo -n | openssl s_client -cipher "$1" -connect $SERVER 2>&1
    }

    function cipher_is_allowed() {
      result=$(test_cipher $cipher)

      if [[ "$result" =~ "Cipher is ${cipher}" || "$result" =~ "Cipher    :" ]]; then
        echo true
      fi
    }

    function echo_cipher_if_allowed() {
      if [[ "$(cipher_is_allowed $1)" = true ]]; then
        echo $1
      fi
    }

    for cipher in ${ciphers[@]}; do
      echo_cipher_if_allowed $cipher
    done
  '

  allowed_ciphers = node_ssh.exec!(command)
  expect(allowed_ciphers).not_to be_nil
  allowed_ciphers.split("\n").map{|item| item.strip}
end
