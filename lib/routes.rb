module Routes
  module Graph
    def self.included(app)
      app.get '/_graph(/:cmp)?(/:ns)?(/:units)?' do
        if params[:cmp].nil?
          @title = "Which Component"
          @choices = ["Pods", "Nodes"]
          haml :choice
        else
          @cmp = params[:cmp]

          if @cmp == "pods"
            if params[:ns].nil?
              @title = "Which Namespace"
              @choices = Kubectl.namespaces
              haml :choice
            else
              if params[:units].nil?
                @title = "Which Values"
                @choices = ["Percent", "Absolute"]
                haml :choice
              else
                @ns     = params[:ns]
                @units  = params[:units]
                @title  = 'Resources Graphs'
                @limits = if @units == "percent"
                            CGI.escape(Base64.encode64(Kubectl.limits("pods",@ns).to_json))
                          end
                haml :graph
              end
            end
          elsif @cmp == "nodes"
            if params[:ns].nil?
              @title = "Which Values"
              @choices = ["Percent", "Absolute"]
              haml :choice
            else
              @ns    = nil
              @units = params[:ns]
              @title = 'Resources Graphs'
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
      app.get '/_cfg' do
        @title = "Configuration"
        haml :config
      end

      app.post '/_cfg' do
        Kubectl.kbcfg(params[:kubeconfig])
        redirect "/"
      end

      app.get '/_busybox(/:r)?' do
        (Kubectl.busybox && halt(200)) if request.xhr?
        (Kubectl.busybox(params[:r]) && redirect("/pods")) if params[:r]
        @title = "Which Namespace"
        @choices = Kubectl.namespaces
        haml :choice
      end
    end
  end
end
