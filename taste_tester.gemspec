# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = 'taste_tester'
  s.version = '0.0.13'
  s.homepage = 'https://github.com/facebook/taste-tester'
  s.platform = Gem::Platform::RUBY
  s.summary = 'Taste Tester'
  s.description = 'Utility for testing Chef changes using chef-zero'
  s.authors = ['Phil Dibowitz', 'Marcin Sawicki']
  s.extra_rdoc_files = ['README.md', 'LICENSE']
  s.files = %w{README.md LICENSE} + Dir.glob('lib/taste_tester/*.rb') +
            Dir.glob('bin/*') + Dir.glob('scripts/*')
  s.executables = 'taste-tester'
  s.license = 'Apache'
  s.add_dependency 'between_meals', '>= 0.0.6'
  # without an explicit dependency, json is resolved to 1.7.7 on Ruby 2.4
  # which doesn't compile.
  s.add_dependency 'json', '>= 2.0.0'
  %w{
    mixlib-config
    colorize
  }.each do |dep|
    s.add_dependency dep
  end
  %w{
    chef-zero
    knife-solo
  }.each do |dep|
    s.add_development_dependency dep
  end
  s.add_development_dependency 'rubocop', '= 0.49.1'
end
