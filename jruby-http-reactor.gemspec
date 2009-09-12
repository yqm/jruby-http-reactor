# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{jruby-http-reactor}
  s.version = "0.0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Anthony Eden"]
  s.date = %q{2009-08-13}
  s.description = %q{}
  s.email = %q{anthonyeden@gmail.com}
  s.extra_rdoc_files = [
    "README.rdoc"
  ]
  s.files = [
    "README.rdoc",
     "Rakefile",
     "VERSION",
     "lib/http_reactor.rb",
     "lib/http_reactor/client.rb",
     "test/client_test.rb",
     "test/test_helper.rb",
     "vendor/httpcore-4.0.1.jar",
     "vendor/httpcore-nio-4.0.1.jar"
  ]
  s.has_rdoc = true
  s.homepage = %q{http://github.com/aeden/jruby-http-reactor}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{JRuby NIO HTTP client.}
  s.test_files = [
    "test/client_test.rb",
     "test/test_helper.rb"
  ]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end