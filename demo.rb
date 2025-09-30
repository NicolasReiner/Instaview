#!/usr/bin/en# Test 2: HTTP method
puts "2. Testing HTTP method:"
begin
  result = Instaview.scrape_with_simple_http("instagram")
  puts "✓ HTTP method working!"
rescue => e
  puts "✗ HTTP method failed: #{e.message}"
end
puts

# Test 3: Selenium method with a working example
puts "3. Testing Selenium method with 'instagram' account:"
begin
  result = Instaview.scrape_instagram_stories("instagram")
  if result[:success]
    puts "✓ Selenium method working! Found #{result[:media_items_found]} media items"
  else
    puts "⚠ Selenium method ran but found no media items"
  end
rescue => e
  puts "✗ Selenium method failed: #{e.message}"
end
putsfrozen_string_literal: true

require_relative 'lib/instaview'

puts "=== Instaview Gem Demo ==="
puts

# Test 1: Basic connectivity
puts "1. Testing basic connectivity:"
Instaview.test_connectivity
puts

# Test 2: HTTP method
puts "2. Testing HTTP method:"
begin
  result = Instaview.scrape_with_simple_http("instagram")
  puts "✓ HTTP method working!"
rescue => e
  puts "✗ HTTP method failed: #{e.message}"
end
puts

# Available methods
puts "4. Available methods:"
puts "   - Instaview.test_connectivity"
puts "   - Instaview.scrape_with_simple_http(username)"  
puts "   - Instaview.scrape_instagram_stories(username) # Selenium-based"
puts

puts "=== Demo Complete ==="