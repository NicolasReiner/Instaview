#!/usr/bin/env ruby
# frozen_string_literal: true

require 'stringio'
require_relative '../lib/instaview'

def silence_output
  original_stdout = $stdout
  original_stderr = $stderr
  $stdout = StringIO.new
  $stderr = StringIO.new
  yield
ensure
  $stdout = original_stdout
  $stderr = original_stderr
end

username = ARGV[0] || 'instagram'

begin
  data = nil

  # Try cache only first (12h TTL)
  silence_output do
    data = Instaview.load_from_cache_only(username)
  end

  # Fallback to async fetch with cache write
  if data.nil?
    silence_output do
      data = Instaview.get_from_cache_or_async(username, max_age_hours: 12)
    end
  end

  # Optionally verify cache can be read after fetch
  silence_output do
    Instaview.load_from_cache_only(username)
  end

  if data && data.is_a?(Hash)
    puts 'success'
    exit 0
  else
    puts 'Error did not receive data'
    exit 1
  end
rescue => e
  puts "Error #{e.message}"
  exit 1
end