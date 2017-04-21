require 'shellwords'

def root_execute_on(ip, command)
  root_prompt = '[sudo] password for vcap: '
  root_prompt_length = root_prompt.length

  output = ssh_gateway.execute_on(ip, command, root: true)
  expect(output).not_to be_nil
  expect(output).to start_with(root_prompt)
  return output.slice(root_prompt_length, output.length - root_prompt_length)
end

def bosh_ssh(host, job, index, command)
  clean_bosh_ssh_output(
    job,
    %x( #{make_bosh_ssh_command(host, job, index, command)} )
  )
end

def clean_bosh_ssh_output(job, output)
  output\
    .split("Cleaning up ssh artifacts")[0]\
    .split(Regexp.new(Regexp.escape("#{job}/") + ".*?$"), 3)[2]\
    .strip
end

def make_bosh_ssh_command(host, job, index, command)
  ssh_gateway_args = [
    "--gateway_host", host,
    "--gateway_user", "vcap",
    "--default_password", "p",
    "--strict_host_key_checking", "no",
  ]

  cmd = ["bosh", "ssh"]
  cmd = cmd + ssh_gateway_args unless host.empty?
  cmd = cmd + [ "#{job}/#{index}", "--", "'#{command}'" ]

  cmd.join(" ")
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

def wait_for_process_start(process_name, job, index)
  18.times do
    sleep 5
    return true if process_running?(process_name, job, index)
  end

  puts "Process #{process_name} did not start within 90 seconds"
  return false
end

def process_running?(process_name, job, index)
  monit_output = bosh_ssh("", job, index, "sudo /var/vcap/bosh/bin/monit summary | grep #{process_name} | grep running")
  !monit_output.strip.empty?
end
