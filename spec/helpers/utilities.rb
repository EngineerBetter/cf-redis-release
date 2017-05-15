require 'open3'
require 'json'

def root_execute_on(ip, command)
  root_prompt = '[sudo] password for vcap: '
  root_prompt_length = root_prompt.length

  output = ssh_gateway.execute_on(ip, command, root: true)
  expect(output).not_to be_nil
  expect(output).to start_with(root_prompt)
  return output.slice(root_prompt_length, output.length - root_prompt_length)
end

def log_is_earlier?(log_line, timestamp)
  match = log_line.scan( /\{.*\}$/ ).first

  return true if match.nil?

  begin
    json_log = JSON.parse(match)
  rescue JSON::ParserError
    return true
  end

  log_timestamp = json_log["timestamp"].to_i
  log_timestamp < timestamp.to_i
end

def drop_log_lines_before(time, log_lines)
  log_lines.lines.drop_while do |log_line|
    log_is_earlier?(log_line, @preprovision_timestamp)
  end
end

def wait_for_process_start(process_name, vm_ip)
  18.times do
    sleep 5
    return true if process_running?(process_name, vm_ip)
  end

  puts "Process #{process_name} did not start within 90 seconds"
  return false
end

def process_running?(process_name, vm_ip)
  monit_output = root_execute_on(vm_ip, "/var/vcap/bosh/bin/monit summary | grep #{process_name} | grep running")
  !monit_output.strip.empty?
end

class Bosh
  def initialize environment, client, client_secret, ca_cert, deployment_name
    @environment = environment
    @client = client
    @client_secret = client_secret
    @ca_cert = ca_cert
    @deployment_name = deployment_name
  end

  def ssh job, node, command, gw_host: nil, gw_user: nil, gw_private_key: nil
    cmd = make_base_command + ['ssh']

    cmd += gateway_params(gw_host, gw_user, gw_private_key) if !gw_host.nil?
    cmd += ["#{job}/#{node.to_s}", "'#{command}'"]
    cmd = cmd.join(' ')

    get_stdout_from_ssh_json JSON.parse(%x( #{cmd} ))
  end

  def make_base_command
    cmd = [
      'bosh-cli',
      '--ca-cert', @ca_cert,
      '-e', @environment,
      '--client', @client,
      '--client-secret', @client_secret,
      '-d', @deployment_name,
      '--json',
    ]
  end

  def gateway_params(gw_host, gw_user, gw_private_key)
    [
      '--gw-host',        gw_host,
      '--gw-user',        gw_user,
      '--gw-private-key', gw_private_key,
    ]
  end

  def get_stdout_from_ssh_json(output)
    output = output['Blocks']
    stdout = []

    inside_stdout_block = false
    output.each do |line|
      if line.include? ': stderr |'
        inside_stdout_block = false
        next
      end

      if line.include? ': stdout |'
        inside_stdout_block = true
        next
      end

      stdout.push(line) if inside_stdout_block
    end

    stdout.join()
  end
end
