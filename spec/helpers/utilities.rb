require 'open3'

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

class BoshSSH
  def initialize job, node
    @job = job
    @node = node
  end

  def with_gateway host, user, pkey
    @gateway_host = host
    @gateway_user = user
    @gateway_identity_file = pkey

    self
  end

  def exec!(command)
    _, stdout, stderr, wait_thr = Open3.popen3(make_cmd(command))
    STDERR.puts stderr.read if !wait_thr.value.success?
    strip_bosh_task_info(stdout.read)
  end

  private
    def strip_bosh_task_info(output)
      output = output.split('Cleaning up ssh artifacts', 2)[0]
      output = output.split('cf-redis-broker/0', 3)[-1]

      output.strip
    end

    def has_gateway?
      !@gateway_host.nil?
    end

    def make_cmd command
      cmd = ['bosh', 'ssh']
      cmd = cmd + gateway_params if has_gateway?

      cmd = cmd + [@job, @node.to_s, "'#{command}'"]
      cmd.join(' ')
    end

    def gateway_params
      [
        '--gateway_host',             @gateway_host,
        '--gateway_user',             @gateway_user,
        '--gateway_identity_file',    @gateway_identity_file,
        '--default_password',         'p',
        '--strict_host_key_checking', 'no',
      ]
    end

    def strip_task_info(output)
      output.split('Cleaning up ssh artifacts')
    end
end
