require 'pp'

unless ARGV.size == 1 && ARGV[0] =~ /_spec.rb/
  puts 'could not run all in one spec, use "rspec spec/something_spec.rb" or "find -iname *_spec.rb -exec rspec {} \;"'
  exit 1
end

def forge_ssh_options host
  options = Net::SSH::Config.for(host)
  options[:user] = ENV['USER']
  options[:keys] = [ ENV['USER_SSH_KEY_PATH'] ]
  options[:keys_only] = true
  options
end

def on_linux_host my_host
  require 'serverspec'
  RSpec.configure do |c|
    c.env = { :LANG => 'C', :LC_ALL => 'C'}
    c.request_pty = true
    c.host = my_host

    c.backend = :ssh
    c.ssh_options = forge_ssh_options host
  end
end

def on_windows_host my_host
  require 'serverspec'
  require 'winrm'

  RSpec.configure do |c|
    c.env = { :LANG => 'C', :LC_ALL => 'C'}
    c.request_pty = true
    c.host = my_host

    c.backend = :winrm
    c.os = { :family => 'windows' }
    endpoint = "http://#{my_host}:5985/wsman"
    winrm = WinRM::WinRMWebService.new(endpoint,
                                       :negotiate,
                                       :user => ENV['WIN_USERNAME'],
                                       :pass => ENV['WIN_PASSWORD']
    )
    winrm.set_timeout 300
    c.winrm = winrm
  end
end

def ssh_on_exec host, command
  require 'net/ssh'
  ssh_options = forge_ssh_options(host)
  Net::SSH.start(host, ssh_options[:user], ssh_options) do |ssh|

    stdout_data = ''
    stderr_data = ''
    exit_status = nil
    exit_signal = nil
    retry_prompt = /^Sorry, try again/

    ssh.open_channel do |channel|
      channel.request_pty do |ch, success|
        abort "Could not obtain pty " if !success
      end
      channel.exec("#{command}") do |ch, success|
        abort "FAILED: couldn't execute command (ssh.channel.exec)" if !success
        channel.on_data do |ch, data|
          if ! data.match /^sudo: unable to resolve host/
            stdout_data += data
            @stdout_handler.call(data) if @stdout_handler
          end
        end

        channel.on_extended_data do |ch, type, data|
          stderr_data += data
        end

        channel.on_request("exit-status") do |ch, data|
          exit_status = data.read_long
        end

        channel.on_request("exit-signal") do |ch, data|
          exit_signal = data.read_long
        end
      end
    end
    ssh.loop
    { :stdout => stdout_data, :stderr => stderr_data, :exit_status => exit_status, :exit_signal => exit_signal }
  end
end
