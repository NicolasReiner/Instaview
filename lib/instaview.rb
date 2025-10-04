# frozen_string_literal: true

require_relative "instaview/version"
require 'selenium-webdriver'
require 'nokogiri'
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'time'
require 'thread'

module Instaview
  class Error < StandardError; end
  
  # @description
  #   Default accessor that returns data for a username. Tries cache first (12h TTL),
  #   otherwise performs an async fetch and returns the fetched result.
  # @Parameter
  #   username: String - Instagram username to retrieve data for (required)
  # @Return values
  #   Hash - Parsed result of the scraping, potentially annotated with `:cached => true`
  # @Errors
  #   ArgumentError - if `username` is nil or empty
  def self.getData(username = nil)
    # Default data accessor: try cache first (12h TTL), otherwise fetch asynchronously and return result
    raise ArgumentError, "username is required" if username.nil? || username.to_s.strip.empty?
    get_from_cache_or_async(username, max_age_hours: 12)
  end

  # @description
  #   Start an asynchronous fetch for the given username and write the result to cache on success.
  # @Parameter
  #   username: String - Instagram username (required)
  #   method: Symbol - :selenium (default) or :simple_http to choose the scraping backend
  # @Return values
  #   Thread - The started thread; `thread.value` returns the Hash result when finished
  # @Errors
  #   ArgumentError - if `username` is nil or empty
  #   RuntimeError or StandardError - on scraping failures raised inside the thread when joining
  def self.fetch_data_async(username, method: :selenium)
    raise ArgumentError, "username is required" if username.nil? || username.to_s.strip.empty?

    Thread.new do
      result = case method
               when :selenium
                 scrape_instagram_stories(username)
               when :simple_http
                 scrape_with_simple_http(username)
               else
                 scrape_instagram_stories(username)
               end

      # Persist to cache on success
      if data_found?(result)
        begin
          write_to_cache(username, result)
        rescue StandardError
          # Ignore cache write failures to avoid affecting callers
        end
      end

      result
    end
  end

  # @description
  #   Try to load from local cache; if missing or older than the given TTL, fetch via async and return the fresh result.
  # @Parameter
  #   username: String - Instagram username (required)
  #   max_age_hours: Integer - Cache TTL in hours (default: 12)
  #   method: Symbol - :selenium (default) or :simple_http
  # @Return values
  #   Hash - Cached or freshly fetched data; cached results will include `:cached => true`
  # @Errors
  #   ArgumentError - if `username` is nil or empty
  def self.get_from_cache_or_async(username, max_age_hours: 12, method: :selenium)
    max_age_seconds = (max_age_hours.to_i * 3600)
    cached = read_from_cache(username, max_age_seconds: max_age_seconds)
    return cached if cached

    t = fetch_data_async(username, method: method)
    t.value # join and return result
  end

  # @description
  #   Return cached data if present and fresh; otherwise return nil. This method does not perform network I/O.
  # @Parameter
  #   username: String - Instagram username (required)
  #   max_age_hours: Integer - Cache TTL in hours (default: 12)
  # @Return values
  #   Hash or nil - Cached data Hash if fresh; nil if missing or stale
  # @Errors
  #   ArgumentError - if `username` is nil or empty
  def self.load_from_cache_only(username, max_age_hours: 12)
    raise ArgumentError, "username is required" if username.nil? || username.to_s.strip.empty?
    max_age_seconds = (max_age_hours.to_i * 3600)
    read_from_cache(username, max_age_seconds: max_age_seconds)
  end

  # --- Cache helpers ---
  # @description
  #   Resolve the directory used to store cache files.
  # @Parameter
  #   None
  # @Return values
  #   String - Absolute path to the cache directory; defaults to ~/.cache/instaview, overridable by INSTAVIEW_CACHE_DIR
  # @Errors
  #   None
  def self.cache_dir
    ENV['INSTAVIEW_CACHE_DIR'] || File.join(Dir.home, ".cache", "instaview")
  end

  # @description
  #   Compute the cache file path for a given username.
  # @Parameter
  #   username: String - Instagram username
  # @Return values
  #   String - Full path to the JSON cache file for the username
  # @Errors
  #   None
  def self.cache_file_for(username)
    sanitized = username.to_s.gsub(/[^a-zA-Z0-9_\-.]/, '_')
    File.join(cache_dir, "#{sanitized}.json")
  end

  # @description
  #   Read a cached result for username if the file exists and is within the max age.
  # @Parameter
  #   username: String - Instagram username
  #   max_age_seconds: Integer - Maximum cache age in seconds (default: 43_200 => 12h)
  # @Return values
  #   Hash or nil - Parsed JSON data with `:cached => true` added, or nil if stale/missing/corrupt
  # @Errors
  #   JSON::ParserError is rescued internally; returns nil when parse fails
  def self.read_from_cache(username, max_age_seconds: 43_200)
    path = cache_file_for(username)
    return nil unless File.exist?(path)

    age = Time.now - File.mtime(path)
    return nil if age > max_age_seconds

    content = File.read(path)
    data = JSON.parse(content, symbolize_names: true)
    return nil unless data_found?(data)
    # annotate so callers can tell it came from cache
    if data.is_a?(Hash)
      data[:cached] = true
    end
    data
  rescue JSON::ParserError
    nil
  end

  # @description
  #   Write the provided data Hash to the cache file for the username.
  # @Parameter
  #   username: String - Instagram username
  #   data: Hash - Data to persist as JSON
  # @Return values
  #   true - On success
  # @Errors
  #   StandardError - on underlying file I/O @errors
  def self.write_to_cache(username, data)
    FileUtils.mkdir_p(cache_dir)
    File.write(cache_file_for(username), JSON.pretty_generate(data))
    true
  end

  def self.data_found?(data)
    return false unless data.is_a?(Hash)

    success = data[:success]
    return true if success == true

    method = data[:method]

    if method == "selenium_storiesig"
      media_found = data[:media_items_found].to_i > 0
      media_present = data[:media_items].is_a?(Array) && !data[:media_items].empty?
      return true if media_found || media_present
    elsif method == "simple_http_curl"
      forms_found = data[:forms_found].to_i > 0
      inputs_found = data[:inputs_found].to_i > 0
      samples_present = data[:sample_images].is_a?(Array) && !data[:sample_images].empty?
      return true if forms_found || inputs_found || samples_present
    end

    false
  end
  private_class_method :data_found?

  # @description
  #   Use Selenium WebDriver to automate StoriesIG and extract media details for a username.
  # @Parameter
  #   username: String - Instagram username (required)
  # @Return values
  #   Hash - Structured result including extracted media and metadata
  # @Errors
  #   Instaview::Error - on Selenium/WebDriver failures or selector timeouts
  def self.scrape_instagram_stories(username = nil)
    target_username = username || ARGV[0] # pass username as argument

    driver = nil
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
      options.binary = chrome_binary if chrome_binary

      driver = Selenium::WebDriver.for :chrome, options: options

      # 1) Go to StoriesIG homepage
      driver.navigate.to "https://storiesig.info/"
      sleep 2

      # 2) Find the specific search input for StoriesIG
      wait = Selenium::WebDriver::Wait.new(timeout: 10)

      input_element = begin
        wait.until do
          element = driver.find_element(:css, 'input.search.search-form__input[placeholder*="username"]')
          element if element.displayed?
        end
      rescue Selenium::WebDriver::Error::TimeoutError
        raise Instaview::Error, "Search input not found with selector: input.search.search-form__input"
      end

      input_element.clear
      input_element.send_keys(target_username)

      # 3) Click the specific search button
      begin
        button_element = driver.find_element(:css, 'button.search-form__button')
        button_element.click
      rescue Selenium::WebDriver::Error::NoSuchElementError
        input_element.send_keys(:return)
      end

      # 4) Wait for results to load and check different possible outcomes
      sleep 3

      # Check for various possible page states
      page_state = "unknown"
      error_message = nil

      # Check if media items loaded
      media_items = driver.find_elements(:css, 'li.profile-media-list__item')
      if media_items.length > 0
        page_state = "media_found"
      else
        # Check for error messages or other states
        sleep 2  # Give it more time
        media_items = driver.find_elements(:css, 'li.profile-media-list__item')

        if media_items.length > 0
          page_state = "media_found_delayed"
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
            rescue StandardError
              # Continue checking other selectors
            end
          end

          page_state = error_found ? "error_found" : "no_media"
        end
      end

      # 5) Extract media content from the specific structure
      html = driver.page_source
      doc = Nokogiri::HTML(html)

      # Extract specific media items using the provided selector
      media_list_items = doc.css('li.profile-media-list__item')

      extracted_media = []
      media_list_items.each do |item|
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
        error_message: error_message,
        success: extracted_media.length > 0,
        debug_info: {
          total_images: all_images.length,
          total_links: all_links.length,
        }
      }

      # Save screenshot for debugging if needed
      if ENV['INSTAVIEW_DEBUG']
        screenshot_path = "/tmp/instaview_debug_#{Time.now.to_i}.png"
        driver.save_screenshot(screenshot_path)
        result[:debug_info][:screenshot_path] = screenshot_path
      end

      result
    rescue Instaview::Error
      raise
    rescue => e
      raise Instaview::Error, "Selenium scraping failed: #{e.message}"
    ensure
      driver&.quit
    end
  end

  # @description
  #   Fetch StoriesIG homepage via curl and parse basic page signals (fallback method).
  # @Parameter
  #   username: String - Instagram username (required)
  # @Return values
  #   Hash - Basic page analysis and sample assets; primarily for diagnostics
  # @Errors
  #   ArgumentError - if `username` is nil or empty
  #   Instaview::Error - if the curl command fails or other errors occur
  def self.scrape_with_simple_http(username = nil)
    target_username = username
    raise ArgumentError, "Username is required for simple HTTP method" if target_username.nil? || target_username.empty?

    begin
      # Simple HTTP approach using curl
      curl_command = "curl -s -L -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36' 'https://storiesig.info/'"

      html_content = `#{curl_command}`

      unless $?.success? && !html_content.empty?
        raise Instaview::Error, "Curl command failed or returned empty content"
      end

      doc = Nokogiri::HTML(html_content)

      # Extract basic page information
      forms = doc.css('form')
      inputs = doc.css('input[type="text"], input[name*="user"]')

      # Look for any existing media or links
      images = doc.css('img').map { |img| img['src'] }.compact.select { |src| src.start_with?('http') }

      {
        username: target_username,
        method: "simple_http_curl",
        forms_found: forms.length,
        inputs_found: inputs.length,
        sample_images: images.first(3),
        message: "Simple HTTP method using curl - shows page structure. For full automation use selenium method."
      }
    rescue Instaview::Error
      raise
    rescue => e
      raise Instaview::Error, "HTTP scraping failed: #{e.message}"
    end
  end
  
  # @description
  #   Verify gem wiring and surface available methods and version info.
  # @Parameter
  #   None
  # @Return values
  #   Hash - Connectivity report
  # @Errors
  #   None
  def self.test_connectivity
    # Simple test method to verify the gem works
    {
      gem_name: "Instaview",
      version: Instaview::VERSION,
      methods_available: [
        "scrape_instagram_stories",
        "scrape_with_simple_http",
        "fetch_data_async",
        "get_from_cache_or_async",
        "load_from_cache_only",
        "getData",
        "test_connectivity"
      ],
      status: "OK"
    }
  end

  # @description
  #   Legacy parsing example for instaview.me; currently a stub.
  # @Parameter
  #   None
  # @Return values
  #   nil
  # @Errors
  #   StandardError - on network/read @errors
  def self.parseData
    # Using a third-party web app, to get Instagram data.
    # Afterwards, we use Nokogiri to parse the HTML.
    require "nokogiri"
    require "open-uri"

    url = "https://www.instaview.me/"
    html = URI.open(url)
    doc = Nokogiri::HTML(html)

    doc.xpath("//profile-media-list__item").map(&:text)
  end
end
