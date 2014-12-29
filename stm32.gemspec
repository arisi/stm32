Gem::Specification.new do |s|
  s.name        = 'stm32'
  s.version     = '0.0.1'
  s.date        = '2014-12-29'
  s.summary     = "Pure Ruby Driver and Flash programmer for stm32 bootstrap "
  s.description = "Pure Ruby Driver and Flash programmer for stm32 bootstrap -- cli and terminal included"
  s.authors     = ["Ari Siitonen"]
  s.email       = 'jalopuuverstas@gmail.com'
  s.files       = ["lib/stm32.rb"]
  s.files      += Dir['http/**/*']
  s.executables << 'stm32_cli.rb'

  s.homepage    = 'https://github.com/arisi/stm32'
  s.license     = 'MIT'
  s.add_runtime_dependency 'srec', '~> 0.0', '>= 0.0.1'
  s.add_runtime_dependency 'minimal-http-ruby', '~> 0.0', '>= 0.0.3'
end
