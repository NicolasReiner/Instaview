# frozen_string_literal: true

require_relative "lib/instaview/version"

Gem::Specification.new do |spec|
  spec.name = "instaview"
  spec.version = Instaview::VERSION
  spec.authors = ["Nicolas Reiner"]
  spec.email = ["nici.ferd@gmail.com"]

  spec.summary = "Instagram viewer gem using Selenium for scraping Instagram stories and media"
  spec.description = "A Ruby gem that uses Selenium to scrape Instagram stories and media from third-party services"
  spec.homepage = "https://github.com/nicolasreiner/instaview"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["allowed_push_host"] = "https://rubygems.org|https://rubygems.pkg.github.com/NicolasReiner"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/nicolasreiner/instaview"
  spec.metadata["changelog_uri"] = "https://github.com/nicolasreiner/instaview/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore])
    end
  end
  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "nokogiri", "~> 1.15"
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "selenium-webdriver", "~> 4.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
