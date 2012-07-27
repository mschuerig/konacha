require "capybara"
require "colorize"
require "builder"
require "ostruct"

module Konacha
  class Runner
    def self.start
      new.run
    end

    attr_reader :io

    def initialize(options = { })
      @io = options[:output] || $stdout
    end

    def run
      before = Time.now

      run_specs

      #io.puts
      #io.puts
      #failed_examples.each do |failure|
      #  io.puts failure.failure_message
      #end

      io.puts
      io.puts
      seconds = "%.2f" % (Time.now - before)
      io.puts "Finished in #{seconds} seconds"
      io.puts "#{examples.size} examples, #{failed_examples.size} failures, #{pending_examples.size} pending"

      write_reports if Konacha.xunit_reports

      passed?
    end

    def session
      @session ||= Capybara::Session.new(Konacha.driver, Konacha.application)
    end

    private

    def examples
      spec_runners.map { |spec_runner| spec_runner.examples }.flatten
    end

    def pending_examples
      examples.select { |example| example.pending? }
    end

    def failed_examples
      examples.select { |example| example.failed? }
    end

    def passed?
      examples.all? { |example| example.passed? }
    end

    def run_specs
      spec_runners.each do |spec_runner|
        spec_runner.run
      end
    end

    def write_reports
      spec_runners.each do |spec_runner|
        report_file(spec_runner.spec) do |out|
          spec_runner.report(out)
        end
      end
    end

    def report_file(spec, &block)
      dir = Konacha.xunit_reports
      FileUtils.mkpath(dir)
      name = spec.path.sub(/\..*$/, '').gsub(/[^[:word:]]/, '-')
      file = "SPEC-#{name}.xml"
      File.open(File.join(dir, file), 'w', &block)
    end

    def spec_runners
      @spec_runners ||= Konacha::Spec.all.map { |spec| SpecRunner.new(self, spec) }
    end
  end

  class SpecRunner
    attr_reader :runner, :spec

    def initialize(runner, spec)
      @runner  = runner
      @spec    = spec
      @results = []
    end

    def run
      session.visit(spec.url)

      dots_printed = 0
      begin
        sleep 0.1
        done, dots = session.evaluate_script('[Konacha.done, Konacha.dots]')
        if dots
          io.write colorize_dots(dots[dots_printed..-1])
          io.flush
          dots_printed = dots.length
        end
      end until done

      results  = JSON.parse(session.evaluate_script('Konacha.getResults()'))
      @results = Suite.from_results(results)
    rescue => e
      msg = [e.inspect]
      msg << e.message unless e.message.blank?
      raise Konacha::Error, "Error communicating with browser process:\n#{msg.join("\n")}"
    end

    def report(out = $stdout)
      @results.each do |suite|
        xml = Builder::XmlMarkup.new(:indent => 2)
        xml.instruct!
        suite.to_xml(xml)
        out.puts(xml.target!)
      end
    end

    def examples
      @results.map(&:all_examples)
    end

    private

    def session
      runner.session
    end

    def io
      runner.io
    end

    def colorize_dots(dots)
      dots = dots.chars.map do |d|
        case d
        when 'E', 'F';
          d.red
        when 'P';
          d.yellow
        when '.';
          d.green
        else
          ; d
        end
      end
      dots.join ''
    end
  end


  class Suite
    attr_reader :title, :stats, :suites, :examples

    def self.from_results(results)
      results.map { |suite| Suite.new(suite) }
    end

    def initialize(suite_result)
      @title    = suite_result['title']
      @stats    = OpenStruct.new(suite_result['stats'])
      @suites   = Array(suite_result['suites']).map { |suite| Suite.new(suite) }
      @examples = Array(suite_result['tests']).map { |example| Example.new(example) }
    end

    def passed?
      @all_passed ||= all_examples.all? { |example| example.passed? }
    end

    def all_examples
      @all_examples ||= suites.map { |suite| suite.all_examples }.flatten + examples
    end

    def to_xml(xml = nil)
      xml   ||= Builder::XmlMarkup.new(:indent => 2)
      attrs = {
        :name     => title,
        :time     => stats.duration.to_f / 1000,
        :tests    => stats.tests,
        :failures => stats.failures,
        :skipped  => stats.pending
      }
      xml.testsuite(attrs) do
        examples.each do |example|
          example.to_xml(xml)
        end
        suites.each do |suite|
          suite.to_xml(xml)
        end
      end
    end
  end

  class Example < OpenStruct
    def passed?
      state == 'passed'
    end

    def pending?
      state == 'pending'
    end

    def failed?
      state == 'failed'
    end

    def short_message
      return '' unless message
      message.lines.first.chomp
    end

    def full_message
      "#{message}\n\n#{stacktrace}"
    end

    def failure_message
      "Failed: #{classname} - #{title}\n#{full_message}"
    end

    def to_xml(xml = nil)
      xml ||= Builder::XmlMarkup.new(:indent => 2)
      #<testcase name="Dpxyz::ResourceMapper::Resource::EntityAdapter when created from an entity delegates attributes to its entity" time="0.005">
      #</testcase>
      xml.testcase(:classname => classname, :name => title, :time => duration.to_f / 1000) do |xml|
        if failed?
          xml.failure(:message => short_message) do |xml|
            xml.cdata!(full_message)
          end
        elsif pending?
          xml.skipped
        end
      end
    end
  end

  class Error < StandardError
  end
end
