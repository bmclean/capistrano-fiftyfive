require 'colorize'
require 'ostruct'

module SSHKit
  module Formatter
    class Abbreviated < SSHKit::Formatter::Abstract

      class << self
        attr_accessor :current_rake_task

        def monkey_patch_rake_task!
          return if @rake_patched

          eval(<<-EVAL)
            class ::Rake::Task
              alias_method :_original_execute_cap55, :execute
              def execute(args=nil)
                SSHKit::Formatter::Abbreviated.current_rake_task = name
                _original_execute_cap55(args)
              end
            end
          EVAL

          @rake_patched = true
        end
      end

      def initialize(io)
        super

        self.class.monkey_patch_rake_task!

        @tasks = {}

        @log_file = fetch(:fiftyfive_log_file) || "capistrano.log"
        @log_file_formatter = SSHKit::Formatter::Pretty.new(
          ::Logger.new(@log_file, 1, 20971520)
        )

        @console = Capistrano::Fiftyfive::Console.new(original_output)
        write_banner
      end

      def print_line(string)
        @console.print_line(string)
      end

      def write_banner
        print_line "Using abbreviated format."
        print_line "Full cap output is being written to #{blue(@log_file)}."
      end

      def write(obj)
        @log_file_formatter << obj

        case obj
        when SSHKit::Command    then write_command(obj)
        when SSHKit::LogMessage then write_log_message(obj)
        end
      end
      alias :<< :write

      private

      def write_log_message(log_message)
        return unless log_message.verbosity > SSHKit::Logger::INFO
        original_output << log_message.to_s + "\n"
      end

      def write_command(command)
        return unless command.verbosity > SSHKit::Logger::DEBUG

        ctx = context_for_command(command)
        number = '%02d' % ctx.number

        if ctx.first_execution?
          if ctx.first_command_of_task?
            print_line "#{clock} #{blue(ctx.task)}"
          end

          description = yellow(ctx.shell_string)
          print_line "      #{number} #{description}"
        end

        if command.finished?
          status = format_command_completion_status(command, number)
          print_line "    #{status}"
        end
      end

      def context_for_command(command)
        task = self.class.current_rake_task.to_s
        task_commands = @tasks[task] ||= []

        shell_string = command.to_s.sub(%r(^/usr/bin/env ), "")

        if task_commands.include?(shell_string)
          first_execution = false
        else
          first_execution = true
          task_commands << shell_string
        end

        number = task_commands.index(shell_string) + 1

        OpenStruct.new({
          :first_execution? => first_execution,
          :first_command_of_task? => (number == 1),
          :number => number,
          :task => task,
          :shell_string => shell_string
        })
      end

      def format_command_completion_status(command, number)
        user = command.user { command.host.user }
        host = command.host.to_s
        user_at_host = [user, host].join("@")

        status = if command.failure?
          red("✘ #{number} #{user_at_host} (see #{@log_file} for details)")
        else
          green("✔ #{number} #{user_at_host}")
        end

        runtime = light_black("%5.3fs" % command.runtime)

        status + " " + runtime
      end

      def clock
        @start_at ||= Time.now
        duration = Time.now - @start_at

        minutes = (duration / 60).to_i
        seconds = (duration - minutes * 60).to_i

        "%02d:%02d" % [minutes, seconds]
      end

      %w(light_black red blue green yellow).each do |color|
        define_method(color) do |string|
          string.to_s.colorize(color.to_sym)
        end
      end
    end
  end
end