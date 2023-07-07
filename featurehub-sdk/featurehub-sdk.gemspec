# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "feature_hub/sdk/version"

Gem::Specification.new do |spec|
  spec.name = "featurehub-sdk"
  spec.version = FeatureHub::Sdk::VERSION
  spec.authors = ["Richard Vowles", "Irina Southwell"]
  spec.email = ["richard@bluetrainsoftware.com"]

  spec.summary = "FeatureHub Ruby SDK"
  spec.description = "FeatureHub Ruby SDK"
  spec.homepage = "https://www.featurehub.io"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.6"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/featurehub-io/featurehub-ruby-sdk"
  spec.metadata["changelog_uri"] = "https://github.com/featurehub-io/featurehub-ruby-sdk/featurehub-sdk/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 1.1"
  spec.add_dependency "faraday", "~> 2"
  spec.add_dependency "ld-eventsource", "~> 2.2.0"
  spec.add_dependency "murmurhash3", "~> 0.1.6"
  spec.add_dependency "sem_version", "~> 2.0.0"
end
