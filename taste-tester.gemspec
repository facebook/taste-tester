Gem::Specification.new do |s|
  s.name = 'taste-tester'
  s.version = '0.0.1'
  s.platform = Gem::Platform::RUBY
  s.summary = 'Taste Tester'
  s.description = 'Utility for testing Chef changes using chef-zero'
  s.authors = ['Phil Dibowitz', 'Marcin Sawicki']
  s.extra_rdoc_files = ['README.md', 'LICENSE', 'taste-untester']
  s.files = %w{README.md LICENSE} + Dir.glob("lib/taste-tester/*.rb") +
    Dir.glob("bin/*")
  s.executables = 'taste-tester'
  s.license = 'Apache'
  %w{
    mixlib-config
    colorize
    between-meals
  }.each do |dep|
    s.add_dependency dep
  end
end
