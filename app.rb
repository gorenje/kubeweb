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

  post '/deployments/:ns/:name/scale' do
    Kubectl.scale(params[:ns],params[:name],params[:scale])
    redirect '/deployments'
  end

  get '/deployments/:ns/:name/scale' do
    @title = "Scale deployment"
    @scale = Kubectl.deployment(params[:ns],params[:name])[-1].split(SpcRE)[1]
    haml :scale
  end

  Cmpnts.each do |cmp|
    get '(/top)?/' + cmp + '/:ns/:name/delete(/:r)?' do
      if params[:r]
        Kubectl.delete(cmp,params[:ns],params[:name]) if params[:r] == "yes"
        redirect "/#{cmp}"
      else
        @title = "Delete #{cmp}"
        haml :choice
      end
    end
  end

  get('(/top)?/pods/:ns/:name/scale') { redirect '/deployments' }

  get '(/top)?/pods/:ns/:name/restart(/:r)?' do
    if params[:r]
      Kubectl.restart(params[:ns],params[:name]) if params[:r] == "yes"
      redirect "/pods"
    else
      @title = "Restart Pod"
      haml :choice
    end
  end

  get '(/top)?/pods/:ns/:name/log' do
    Kubectl.watch(params[:ns], params[:name]) ; redirect('/pods')
  end

  get '(/top)?/nodes/:name/:ignore/desc' do
    Kubectl.describe(nil, "nodes", params[:name])
    redirect('/top/nodes')
  end

  get '(/top)?/:cmp/:ns/:name/desc' do
    Kubectl.describe(params[:ns], params[:cmp], params[:name])
    redirect('/'+params[:cmp])
  end

  get '(/top)?/pods/:ns/:name/shell' do
    Kubectl.shell(params[:ns], params[:name]) ; redirect('/pods')
  end

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

  include Routes::ClusterActions
  include Routes::Graph

  get '/' do
    haml ".text-center\n  %a{:href => '/_cfg'} Config"
  end

  error(404) do
    haml ".text-center\n  Action/Page not supported."
  end
end
