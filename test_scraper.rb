#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/instaview'

# Test the scraping functionality
begin
  puts "Testing Instagram viewer with username: instagram"
  result = Instaview.scrape_instagram_stories("instagram")
  puts "Scraping completed successfully!"
  puts "Result keys: #{result.keys}"
rescue => e
  puts "Error during scraping: #{e.message}"
  puts e.backtrace.first(5)
end