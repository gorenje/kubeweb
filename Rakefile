require 'rubygems'
require 'bundler'
require 'bundler/setup'

require 'dotenv'
Dotenv.load('.env') if File.exists?('.env')

Dir[File.join(File.dirname(__FILE__), 'lib', 'tasks','*.rake')].each do |f|
  load f
end

desc "Start a pry shell"
task :shell do
  require 'pry'
  Pry.editor = ENV['PRY_EDITOR'] || ENV['EDITOR'] || 'emacs'
  Pry.start
end
