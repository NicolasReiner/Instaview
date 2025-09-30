# Instaview

A Ruby gem that uses Selenium WebDriver to scrape Instagram stories and media from third-party services like StoriesIG. This gem provides a programmatic interface to fetch Instagram content without using the official Instagram API.

## Features

- Scrapes Instagram stories and media using Selenium WebDriver
- Targets StoriesIG.info for anonymous Instagram viewing
- Extracts media items with images, captions, download links, and metadata
- Headless browser automation with fallback HTTP method
- JSON output format with structured data
- Command-line interface with multiple methods

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'instaview'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install instaview

## Setup

After installation, you may need to install Chrome/Chromium for the Selenium method:

```bash
# Ubuntu/Debian
sudo apt-get install chromium-browser

# Or run the setup script
./bin/setup_selenium
```

## Usage

### Command Line

```bash
# Test the gem
ruby bin/instaview test

# Using the HTTP method (recommended, more reliable)
ruby bin/instaview instagram http

# Using the Selenium method (full automation, may have issues with anti-bot measures)
ruby bin/instaview instagram selenium

# Or if installed as a gem
instaview username_here http
```

### Ruby Code

```ruby
require 'instaview'

# Test connectivity
Instaview.test_connectivity

# Use simple HTTP method (recommended)
result = Instaview.scrape_with_simple_http("instagram")

# Or try Selenium method (full automation)
result = Instaview.scrape_instagram_stories("instagram")

puts result
```

### Example Output

#### Selenium Method (Full Automation)
```json
{
  "username": "instagram",
  "method": "selenium_storiesig",
  "media_items_found": 3,
  "media_items": [
    {
      "image_url": "https://media.storiesig.info/get?__sig=...",
      "alt_text": "preview",
      "caption": "Some caption text.",
      "download_url": "https://media.storiesig.info/get?__sig=...",
      "likes": "8",
      "time": "2 weeks ago",
      "time_title": "9/13/2025, 8:20:20 AM"
    }
  ],
  "success": true
}
```

#### HTTP Method (Page Analysis)
```json
{
  "username": "instagram",
  "method": "simple_http_curl",
  "page_title": "Anonymous Instagram Story Viewer ✔️ ❤️ StoriesIG",
  "forms_found": 1,
  "inputs_found": 1,
  "message": "Simple HTTP method using curl - shows page structure."
}
```

## Dependencies

- Ruby >= 3.2.0
- selenium-webdriver (~> 4.0)
- httparty (~> 0.21)
- nokogiri (~> 1.15)
- json (~> 2.0)
- curl (system dependency)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Troubleshooting

### Selenium Issues

If you encounter issues with Selenium WebDriver:

1. Make sure Chrome/Chromium is installed:
   ```bash
   sudo apt-get install chromium-browser
   # or
   ./bin/setup_selenium
   ```

2. Use the HTTP method as a fallback:
   ```bash
   instaview username http
   ```

3. Check if the selectors need updating (websites change frequently)

### General Issues

- Some sites have anti-bot measures that may block automated requests
- The HTTP method provides basic page structure analysis
- For full automation, Selenium is needed but may face restrictions

## Legal Notice

This gem is for educational purposes only. Please respect Instagram's terms of service and the terms of service of any third-party websites you scrape. The authors are not responsible for any misuse of this software.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/nicolasreiner/instaview. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/nicolasreiner/instaview/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Instaview project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/nicolasreiner/instaview/blob/master/CODE_OF_CONDUCT.md).