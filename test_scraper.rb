#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require_relative 'lib/instaview'

username = ARGV[0] || 'instagram'

begin
  cache_path = Instaview.cache_file_for(username)
  FileUtils.rm_f(cache_path)

  initial_cache = Instaview.load_from_cache_only(username)
  raise "cache should be empty" unless initial_cache.nil?

  fetch_thread = Instaview.fetch_data_async(username, method: :simple_http)
  raise "fetch_data_async must return a Thread" unless fetch_thread.is_a?(Thread)

  fresh_result = fetch_thread.value
  raise "fetch did not return data" unless fresh_result.is_a?(Hash)
  raise "fresh result should not be marked cached" if fresh_result[:cached]

  cached_result = Instaview.load_from_cache_only(username)
  raise "cache not populated" if cached_result.nil?
  raise "cached result missing cached flag" unless cached_result[:cached]

  puts 'success'
  exit 0
rescue => e
  puts "Error #{e.message}"
  exit 1
end