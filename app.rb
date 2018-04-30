['sinatra/base', 'haml', 'thin', 'base64'].map { |a| require(a) }

require_relative 'lib/constants'
require_relative 'lib/kubectl'
require_relative 'lib/helpers'
require_relative 'lib/routes'

class Webapp < Sinatra::Base
  set :show_exceptions, :after_handler

  helpers do
    include ViewHelpers
  end

  include Routes::Actions::Scale
  include Routes::Actions::Delete
  include Routes::Actions::Restart
  include Routes::Actions::Log
  include Routes::Actions::Desc
  include Routes::Actions::Shell
  include Routes::Actions::Edit
  include Routes::ClusterActions
  include Routes::Graph

  get '/top/:cmp' do
    @title = "All " + params[:cmp]
    @allrows = Kubectl.top(params[:cmp])
    haml :table
  end

  Cmpnts.each do |element|
    get '/'+element do
      @title = "All " + element.capitalize
      @allrows = Kubectl.get(element)
      haml :table
    end
  end

  get '/top' do
    @title = "Which Top"
    @choices = ["Pods", "Nodes"]
    haml :choice
  end

  get '/' do
    haml ".text-center\n  %a{:href => '/_cfg'} Config"
  end

  error(404) do
    haml ".text-center\n  Action/Page not supported."
  end
end
