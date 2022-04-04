# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cocoapods-xlbuild/gem_version.rb'

Gem::Specification.new do |spec|
  spec.name          = 'cocoapods-xlbuild'
  spec.version       = CocoapodsXLbuild::VERSION
  spec.authors       = ['林鹏']
  spec.email         = ['linpeng.dev@gmail.com']
  spec.description   = %q{工程静态库编译，提高编译速度.}
  spec.summary       = %q{工程静态库编译，提高编译速度.}
  spec.homepage      = 'https://github.com/Jacky-LinPeng/cocoapods-xlbuild.git'
  spec.license       = 'MIT'

  spec.files = Dir['lib/**/*']
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']
end
