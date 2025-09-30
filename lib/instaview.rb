# frozen_string_literal: true

require_relative "instaview/version"
require 'selenium-webdriver'
require 'nokogiri'
require 'json'
require 'net/http'
require 'uri'

module Instaview
  class Error < StandardError; end
  
  def self.getData(username = nil)
    throw NotImplementedError, "This is a placeholder method."
  end

  def self.scrape_instagram_stories(username = nil)
    target_username = username || ARGV[0] # pass username as argument

    begin
      # Setup Selenium WebDriver with headless Chrome
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless=new')
      options.add_argument('--no-sandbox')
      options.add_argument('--disable-dev-shm-usage')
      options.add_argument('--disable-gpu')
      options.add_argument('--disable-extensions')
      options.add_argument('--disable-background-timer-throttling')
      options.add_argument('--disable-backgrounding-occluded-windows')
      options.add_argument('--disable-renderer-backgrounding')
      options.add_argument('--window-size=1920,1080')
      options.add_argument('--remote-debugging-port=9222')
      options.add_argument('--user-data-dir=/tmp/chrome-user-data')

      # Try different Chrome/Chromium binaries
      chrome_paths = [
        "/snap/bin/chromium",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        "/usr/bin/google-chrome"
      ]
      
      chrome_binary = chrome_paths.find { |path| File.exist?(path) }
      
      if chrome_binary
        options.binary = chrome_binary
        puts "Using Chrome binary: #{chrome_binary}"
      end
      
      driver = Selenium::WebDriver.for :chrome, options: options

      # 1) Go to StoriesIG homepage
      driver.navigate.to "https://storiesig.info/"
      sleep 2

      # 2) Find the specific search input for StoriesIG
      puts "Looking for search input..."
      input_element = nil
      
      # Wait for page to load and find the specific input
      wait = Selenium::WebDriver::Wait.new(timeout: 10)
      
      begin
        input_element = wait.until do
          element = driver.find_element(:css, 'input.search.search-form__input[placeholder*="username"]')
          element if element.displayed?
        end
      rescue Selenium::WebDriver::Error::TimeoutError
        raise "Search input not found with selector: input.search.search-form__input"
      end

      puts "Found search input, entering username: #{target_username}"
      input_element.clear
      input_element.send_keys(target_username)

      # 3) Click the specific search button
      puts "Looking for search button..."
      begin
        button_element = driver.find_element(:css, 'button.search-form__button')
        puts "Found search button, clicking..."
        button_element.click
      rescue Selenium::WebDriver::Error::NoSuchElementError
        puts "Search button not found, trying Enter key..."
        input_element.send_keys(:return)
      end

      # 4) Wait for results to load and check different possible outcomes
      puts "Waiting for results to load..."
      sleep 3
      
      # Check for various possible page states
      page_state = "unknown"
      error_message = nil
      
      # Check if media items loaded
      media_items = driver.find_elements(:css, 'li.profile-media-list__item')
      if media_items.length > 0
        page_state = "media_found"
        puts "Found #{media_items.length} media items!"
      else
        # Check for error messages or other states
        sleep 2  # Give it more time
        media_items = driver.find_elements(:css, 'li.profile-media-list__item')
        
        if media_items.length > 0
          page_state = "media_found_delayed"
          puts "Found #{media_items.length} media items after delay!"
        else
          # Look for common error indicators
          error_selectors = [
            '.error', '.alert', '.warning', 
            '[class*="error"]', '[class*="not-found"]',
            'p:contains("not found")', 'div:contains("error")'
          ]
          
          error_found = false
          error_selectors.each do |selector|
            begin
              error_elements = driver.find_elements(:css, selector)
              if error_elements.any?
                error_message = error_elements.first.text
                error_found = true
                break
              end
            rescue
              # Continue checking other selectors
            end
          end
          
          if error_found
            page_state = "error_found"
            puts "Error found: #{error_message}"
          else
            page_state = "no_media"
            puts "No media items found, checking page content..."
          end
        end
      end

      # 5) Extract media content from the specific structure
      html = driver.page_source
      doc = Nokogiri::HTML(html)

      # Extract specific media items using the provided selector
      media_list_items = doc.css('li.profile-media-list__item')
      
      extracted_media = []
      media_list_items.each_with_index do |item, index|
        media_data = {}
        
        # Extract image source
        img_element = item.css('.media-content__image').first
        if img_element
          media_data[:image_url] = img_element['src']
          media_data[:alt_text] = img_element['alt']
        end
        
        # Extract caption
        caption_element = item.css('.media-content__caption').first
        media_data[:caption] = caption_element&.text&.strip
        
        # Extract download link
        download_element = item.css('a.button.button--filled.button__download').first
        media_data[:download_url] = download_element['href'] if download_element
        
        # Extract metadata
        like_element = item.css('.media-content__meta-like').first
        media_data[:likes] = like_element&.text&.strip
        
        time_element = item.css('.media-content__meta-time').first
        media_data[:time] = time_element&.text&.strip
        media_data[:time_title] = time_element['title'] if time_element
        
        extracted_media << media_data unless media_data.empty?
      end

      # Also extract any general images and links
      all_images = doc.css('img').map { |img| img['src'] }.compact.uniq.reject(&:empty?)
      all_links = doc.css('a').map { |link| link['href'] }.compact.uniq.reject(&:empty?)
      download_links = doc.css('a.button__download').map { |link| link['href'] }.compact.uniq

      result = {
        username: target_username,
        method: "selenium_storiesig",
        page_state: page_state,
        media_items_found: extracted_media.length,
        media_items: extracted_media,
        all_images: all_images.select { |img| img.start_with?('http') }.first(10), # Limit output
        download_links: download_links,
        instagram_links: all_links.select { |l| l.include?("instagram") || l.include?("storiesig") }.first(10),
        page_title: doc.css('title').text,
        error_message: error_message,
        success: extracted_media.length > 0,
        debug_info: {
          total_images: all_images.length,
          total_links: all_links.length,
          page_url: driver.current_url
        }
      }

      # Save screenshot for debugging if needed
      if ENV['INSTAVIEW_DEBUG']
        screenshot_path = "/tmp/instaview_debug_#{Time.now.to_i}.png"
        driver.save_screenshot(screenshot_path)
        result[:debug_info][:screenshot_path] = screenshot_path
        puts "Debug screenshot saved to: #{screenshot_path}"
      end

      puts JSON.pretty_generate(result)

      result
    rescue => e
      puts "Error: #{e.message}"
      puts "Make sure Chrome/Chromium is installed for Selenium WebDriver"
      raise e
    ensure
      driver&.quit
    end
  end

  def self.scrape_with_simple_http(username = nil)
    target_username = username
    throw ArgumentError, "Username is required for simple HTTP method" if target_username.nil? || target_username.empty?
    begin
      # Simple HTTP approach using curl
      puts "Trying to fetch page with curl..."
      
      curl_command = "curl -s -L -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36' 'https://storiesig.info/'"
      
      html_content = `#{curl_command}`
      
      if $?.success? && !html_content.empty?
        doc = Nokogiri::HTML(html_content)
        
        # Extract basic page information
        title = doc.css('title').text
        forms = doc.css('form')
        inputs = doc.css('input[type="text"], input[name*="user"]')
        
        # Look for any existing media or links
        images = doc.css('img').map { |img| img['src'] }.compact.select { |src| src.start_with?('http') }
        links = doc.css('a').map { |link| link['href'] }.compact.select { |href| href.include?('instagram') || href.include?('media') }
        
        result = {
          username: target_username,
          method: "simple_http_curl",
          page_title: title,
          forms_found: forms.length,
          inputs_found: inputs.length,
          sample_images: images.first(3),
          instagram_links: links.first(5),
          message: "Simple HTTP method using curl - shows page structure. For full automation use selenium method."
        }
        
        puts JSON.pretty_generate(result)
        result
      else
        raise "Curl command failed or returned empty content"
      end
    rescue => e
      puts "Error with simple HTTP method: #{e.message}"
      puts "Try using scrape_instagram_stories method instead"
      raise e
    end
  end
  
  def self.test_connectivity
    # Simple test method to verify the gem works
    puts "Testing Instaview gem connectivity..."
    
    result = {
      gem_name: "Instaview",
      version: Instaview::VERSION,
      methods_available: ["scrape_instagram_stories", "scrape_with_simple_http", "test_connectivity"],
      status: "OK"
    }
    
    puts JSON.pretty_generate(result)
    result
  end

  def self.parseData
    # Using a third-party web app, to get Instagram data.
    # Afterwards, we use Nokogiri to parse the HTML.
    require "nokogiri"
    require "open-uri"

    url = "https://www.instaview.me/"
    html = URI.open(url)
    doc = Nokogiri::HTML(html)

    doc.xpath("//profile-media-list__item").each do |item|
      puts item.text
    end
  end
end
