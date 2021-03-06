module Routes
  module Actions
    module Delete
      def self.included(app)
        Cmpnts.each do |cmp|
          app.get '(/top)?/' + cmp + '/:ns/:name/delete(/:r)?' do
            if params[:r]
              if params[:r] == "yes"
                Kubectl.delete(cmp,params[:ns],params[:name])
              end
              redirect "/#{cmp}"
            else
              @select = ": Delete #{cmp}?"
              haml :choice
            end
          end
        end
      end
    end

    module Restart
      def self.included(app)
        app.get '(/top)?/pods/:ns/:name/restart(/:r)?' do
          if params[:r]
            Kubectl.restart(params[:ns],params[:name]) if params[:r] == "yes"
            redirect "/pods"
          else
            @select = ": Restart Pod?"
            haml :choice
          end
        end
      end
    end

    module Scale
      def self.included(app)
        app.post '/deployments/:ns/:name/scale' do
          Kubectl.scale(params[:ns],params[:name],params[:scale])
          redirect '/deployments'
        end

        app.get '/deployments/:ns/:name/scale' do
          @scale = Kubectl.deployment(params[:ns],params[:name])[-1].
                     split(SpcRE)[1]
          haml :scale
        end

        app.get('(/top)?/pods/:ns/:name/scale') do
          redirect '/deployments'
        end
      end
    end

    module Shell
      def self.included(app)
        app.get '(/top)?/pods/:ns/:name/shell' do
          Kubectl.shell(params[:ns], params[:name])
          redirect('/pods')
        end

        app.get '/_events/:ns/:name/shell' do
          Kubectl.shell(params[:ns], params[:name])
          redirect('/_events')
        end
      end
    end

    module Log
      def self.included(app)
        app.get '(/top)?/pods/:ns/:name/log' do
          Kubectl.watch(params[:ns], params[:name])
          redirect('/pods')
        end

        app.get '/_events/:ns/:name/log' do
          Kubectl.watch(params[:ns], params[:name])
          redirect('/_events')
        end
      end
    end

    module Desc
      def self.included(app)
        app.get '(/top)?/nodes/:name/:ignore/desc' do
          Kubectl.describe(nil, "nodes", params[:name])
          redirect('/top/nodes')
        end

        app.get '/_events/:ns/:name/desc' do
          halt(404)
        end

        app.get '(/top)?/:cmp/:ns/:name/desc' do
          Kubectl.describe(params[:ns], params[:cmp], params[:name])
          redirect('/'+params[:cmp])
        end
      end
    end

    module Edit
      def self.included(app)
        app.get '(/top)?/pods/:ns/:name/edit' do
          Kubectl.edit(params[:ns], "pods", params[:name])
          redirect('/pods')
        end

        ["deployments", "services", "ingress", "pvc"].each do |cmp|
          app.get "/#{cmp}/:ns/:name/edit" do
            Kubectl.edit(params[:ns], cmp, params[:name])
            redirect("/#{cmp}")
          end
        end
      end
    end
  end

  module Graph
    def self.included(app)
      app.get '/_graph(/:cmp)?(/:ns)?(/:units)?' do
        if params[:cmp].nil?
          @select = " Component"
          @choices = ["Pods", "Nodes"]
          haml :choice
        else
          @cmp = params[:cmp]

          if @cmp == "pods"
            if params[:ns].nil?
              @select = " Namespace"
              @choices = Kubectl.namespaces
              haml :choice
            else
              if params[:units].nil?
                @select = ": Which Values?"
                @choices = ["Percent", "Absolute"]
                haml :choice
              else
                @ns     = params[:ns]
                @units  = params[:units]
                @limits = if @units == "percent"
                            CGI.escape(Base64.encode64(Kubectl.limits("pods",@ns).to_json))
                          end
                haml :graph
              end
            end
          elsif @cmp == "nodes"
            if params[:ns].nil?
              @select = ": Which Values?"
              @choices = ["Percent", "Absolute"]
              haml :choice
            else
              @ns    = nil
              @units = params[:ns]
              haml :graph
            end
          else
            halt(404)
          end
        end
      end

      app.get '/_graph.json' do
        content_type :json
        perc = params[:u] == "percent"
        { :data =>
          case params[:c]
          when "nodes"
            case params[:t]
            when 'cpu'
              Kubectl.top("nodes")[1..-1].map do |l|
                d = l.split(SpcRE) ; gh(d[0], d[perc ? 2 : 1].to_i)
              end
            when 'mem'
              Kubectl.top("nodes")[1..-1].map do |l|
                d = l.split(SpcRE) ; gh(d[0], d[perc ? 4 : 3].to_i)
              end
            end
          when "pods"
            if perc
              limits = JSON(Base64.decode64(params[:d]))
              case params[:t]
              when 'cpu'
                Kubectl.top("pods",params[:ns])[1..-1].map do |l|
                  d = l.split(SpcRE)
                  n = d[0..1].join(":")
                  gh(n, perc(:cpu,d[2].to_i,(limits[n]||{})["limits"]))
                end
              when 'mem'
                Kubectl.top("pods",params[:ns])[1..-1].map do |l|
                  d = l.split(SpcRE)
                  n = d[0..1].join(":")
                  gh(n, perc(:mem,d[3].to_i,(limits[n]||{})["limits"]))
                end
              end
            else
              case params[:t]
              when 'cpu'
                Kubectl.top("pods",params[:ns])[1..-1].map do |l|
                  d = l.split(SpcRE); gh(d[0..1].join(":"), d[2].to_i)
                end
              when 'mem'
                Kubectl.top("pods",params[:ns])[1..-1].map do |l|
                  d = l.split(SpcRE); gh(d[0..1].join(":"), d[3].to_i)
                end
              end
            end
          end || []
        }.to_json
      end
    end
  end

  module ClusterActions
    def self.included(app)
      app.get '/_events' do
        @allrows = Kubectl.get("events")
        haml :table
      end

      app.get '/_cfg' do
        haml :config
      end

      app.post '/_cfg' do
        Kubectl.kbcfg(params[:kubeconfig])
        redirect "/"
      end

      app.get '/_busybox(/:r)?' do
        (Kubectl.busybox && halt(200)) if request.xhr?
        (Kubectl.busybox(params[:r]) && redirect("/pods")) if params[:r]
        @select = " Namespace"
        @choices = Kubectl.namespaces
        haml :choice
      end
    end
  end
end
