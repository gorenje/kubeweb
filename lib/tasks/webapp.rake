# coding: utf-8
['sinatra','haml','thin'].map { |a| require(a) }

namespace :webapp do
  desc "Start application"
  task :start do
    Thin::Server.new((ENV['PORT']||'3001').to_i).tap do |s|
      s.app = Webapp
    end.start
  end
end

class Webapp < Sinatra::Base
  enable :inline_templates
  set :show_exceptions, :after_handler

  YesNo  = ["Yes", "No"]
  SpcRE  = /[[:space:]]+/
  Cmpnts = ["deployments", "pods", "services", "ingress", "pvc"]
  MxPler = {:h=>3600,:m=>60,:d=>86400,:Gi=>1024}
  Nrm    = Proc.new { |v,u| v.to_i * (MxPler[(u||"").to_sym] || 1) }

  PidOfForeman = "\\$(pidof 'foreman: master')"
  PidLookup = {
    "pushtech" => {
      "website"            => PidOfForeman,
      "notificationserver" => PidOfForeman,
      "imageserver"        => PidOfForeman,
    }
  }

  module Kubectl
    extend self
    def kctl(cmdline)
      `kubectl --kubeconfig="#{kbcfg}" #{cmdline}`.split(/\n/)
    end

    def kbcfg(v = nil)
      v.nil? ? ENV['KUBECONFIG'] : (ENV['KUBECONFIG'] = v)
    end

    def namespaces
      get("namespaces")[1..-1].map { |a| a.split(SpcRE)[0] }
    end

    def scale(ns,name,scale)
      kctl("scale deployment -n #{ns} #{name} --replicas=#{scale}")
    end

    def delete(cmp, ns, name)
      kctl("delete #{cmp.to_s} -n #{ns} --force #{name}")
    end

    def top(cmp, ns = nil)
      kctl("top #{cmp} " +
           (cmp == "pods" ? ((ns ? "-n #{ns}" : "--all-namespaces") +
                             " --containers=true") : ""))
    end

    def get(cmp)
      kctl("get #{cmp.to_s} --all-namespaces --output=wide")
    end

    def deployment(ns,name)
      kctl("get deployments -n #{ns} #{name}")
    end

    def version
      d = JSON(kctl("version --output=json").join) ; v = 'Version'
      ["client","server"].map { |a| "#{a}: #{d[a+v]['git'+v]}" }.join(" & ")
    end

    def osascript(script)
      system("osascript -e 'tell application \"Terminal\" to do script " +
             "\"kubectl #{script} --kubeconfig=\\\"#{kbcfg}\\\"\"'")
    end

    def busybox(ns = nil)
      osascript("run -it busybox-#{(rand*1000000).to_i.to_s(16)} " +
                "-n #{ns || 'default'} --image=busybox --restart=Never")
    end

    def watch(ns,name) ; osascript("logs #{_c(ns,name)} --follow=true") ; end
    def shell(ns,name) ; osascript("exec #{_c(ns,name)} -it /bin/bash") ; end
    def describe(ns,cmp,name);osascript("describe #{cmp} #{_c(ns,name)}");end

    def restart(ns,name)
      pid = (PidLookup[ns]||{})[name.split(/-/)[0..-3].join("-")] || "1"
      kctl("exec #{name} -n #{ns} -it -- /bin/bash -c \"kill #{pid}\"")
    end

    def desc(cmp,ns)
      kctl("describe #{cmp} -n #{ns}")
    end

    def limits(cmp,ns)
      podname, containername = nil, []
      data = desc(cmp,ns)
      Hash.new { |h, k| h[k] = {} }.tap do |r|
        data.each_with_index do |line,idx|
          case line
          when /^Name:/
            podname = line.split(SpcRE).last
          when /Container ID:/
            containername = data[idx-1].strip.sub(/:/,'')
          when /Limits:/
            r[podname+":"+containername][:limits] = {
              :cpu => data[idx+1].split(SpcRE).last,
              :mem => data[idx+2].split(SpcRE).last
            }
          when /Requests:/
            r[podname+":"+containername][:requests] = {
              :cpu => data[idx+1].split(SpcRE).last,
              :mem => data[idx+2].split(SpcRE).last
            }
          end
        end
      end
    end

    def external_ip
      (kctl("describe svc nginx --namespace nginx-ingress").
         select { |a| a =~ /LoadBalancer Ingress/ }.first||"").split(SpcRE).last
    end

    def _c(ns,name)
      name,container = name =~ /:/ ? name.split(/:/) : [name,nil]
      "#{name} #{container ? '-c ' + container : ''} -n #{ns}"
    end
  end

  helpers do
    def perc(what,value,limits)
      return -1 if limits.nil? or limits[what.to_s].nil?
      max = limits[what.to_s].to_i
      ((value / max.to_f) * 100).to_i
    end

    def header_row(line)
      (line + " Actions").split(SpcRE).map { |v| "<th>#{v}</th>" }.join("\n")
    end

    def cell(value)
      o = value =~ /^([0-9]+)(m|Mi|Gi|%|d|h)/ ? Nrm.call($1,$2) : value
      "<td data-order='#{o}'>#{value}</td>"
    end

    def line_to_row(line,idx)
      (c = line.split(SpcRE)).map { |v| cell(v) }.join("\n") + "<td>" +
        ["delete", "log", "desc", "scale", "shell", "restart"].map do |v|
        "<a class='_#{v}' href='#{request.path}/#{c[0]}/#{c[1]}/#{v}'>#{v}</a>"
      end.join("\n") + "</td>"
    end
    def gh(n,v) ; { :name => n, :value => v } ; end
  end

  post '/deployments/:ns/:name/scale' do
    Kubectl.scale(params[:ns],params[:name],params[:scale])
    redirect '/deployments'
  end

  get '/deployments/:ns/:name/scale' do
    @title = "Scale deployment"
    @scale = Kubectl.deployment(params[:ns],params[:name])[-1].split(SpcRE)[1]
    haml :scale, :layout => :layout
  end

  Cmpnts.each do |cmp|
    get '(/top)?/' + cmp + '/:ns/:name/delete(/:r)?' do
      if params[:r]
        Kubectl.delete(cmp,params[:ns],params[:name]) if params[:r] == "yes"
        redirect "/#{cmp}"
      else
        @title = "Delete #{cmp}"
        haml :choice, :layout => :layout
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
      haml :choice, :layout => :layout
    end
  end

  get '(/top)?/pods/:ns/:name/log' do
    Kubectl.watch(params[:ns], params[:name]) ; redirect('/pods')
  end

  get '/top/nodes/:name/:ignore/desc' do
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
    @title = "All " + params[:cmp] ; @allrows = Kubectl.top(params[:cmp])
    haml :table, :layout => :layout
  end

  Cmpnts.each do |element|
    get '/'+element do
      @title = "All " + element.capitalize ; @allrows = Kubectl.get(element)
      haml :table, :layout => :layout
    end
  end

  get '/top' do
    @title = "Which Top" ; @choices = ["Pods", "Nodes"]
    haml :choice, :layout => :layout
  end

  get '/_busybox(/:r)?' do
    (Kubectl.busybox && halt(200)) if request.xhr?
    (Kubectl.busybox(params[:r]) && redirect("/pods")) if params[:r]
    @title = "Which Namespace" ; @choices = Kubectl.namespaces
    haml :choice, :layout => :layout
  end

  get '/_cfg' do
    @title = "Configuration" ; haml(:config, :layout => :layout)
  end

  get '/_ip' do
    @title = "External Ip" ; haml(Kubectl.external_ip, :layout => :layout)
  end

  post '/_cfg' do
    Kubectl.kbcfg(params[:kubeconfig]) ; redirect "/"
  end

  get '/_graph(/:cmp)?(/:ns)?(/:units)?' do
    if params[:cmp].nil?
      @title = "Which Component" ; @choices = ["Pods", "Nodes"]
      haml :choice, :layout => :layout
    else
      @cmp = params[:cmp]
      if @cmp == "pods"
        if params[:ns].nil?
          @title = "Which Namespace" ; @choices = Kubectl.namespaces
          haml :choice, :layout => :layout
        else
          if params[:units].nil?
            @title = "Which Values" ; @choices = ["Percent", "Absolute"]
            haml :choice, :layout => :layout
          else
            @ns     = params[:ns]
            @units  = params[:units]
            @title  = 'Resources Graphs'
            @limits = if @units == "percent"
              CGI.escape(Base64.encode64(Kubectl.limits("pods",@ns).to_json))
            end
            haml(:graph, :layout => :layout)
          end
        end
      elsif @cmp == "nodes"
        @title = 'Resources Graphs' ; haml(:graph, :layout => :layout)
        if params[:ns].nil?
          @title = "Which Values" ; @choices = ["Percent", "Absolute"]
          haml :choice, :layout => :layout
        else
          @ns    = nil
          @units = params[:ns]
          @title = 'Resources Graphs'
          haml(:graph, :layout => :layout)
        end
      else
        halt(404)
      end
    end
  end

  get '/_graph.json' do
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

  get '/' do
    @title = "All Actions"
    haml("%a{:href => '/_cfg'} Config", :layout => :layout)
  end

  error(404) do
    haml "Action/Page not supported.", :layout => :layout
  end
end

__END__

@@ layout
%html
  %head
    %link{:href => "https://cdn.datatables.net/v/bs4/dt-1.10.16/datatables.min.css", :rel => "stylesheet"}
    %link{:href => "https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/css/bootstrap.min.css", :rel => "stylesheet"}
    %script{:src => "https://cdnjs.cloudflare.com/ajax/libs/jquery/3.3.1/jquery.min.js"}
    %script{:src => "https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.12.9/umd/popper.min.js"}
    %script{:src => "https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/js/bootstrap.min.js"}
    %script{:src => "https://cdn.datatables.net/v/bs4/dt-1.10.16/datatables.min.js"}
    %script{:src => "https://cdn.datatables.net/v/bs4/dt-1.10.16/datatables.min.js"}
    %script{:src => "https://cdnjs.cloudflare.com/ajax/libs/highcharts/6.0.7/highcharts.js"}
    %title= @title || 'No Title'
  %body
    :javascript
      const NotApp = function(){ alert('N/A') }
      $(document).ready(function() {
        $('a._log, a._shell, a._busybox, a._desc').click(function(event){
          $.get($(event.target).attr('href')).fail(NotApp);
          return false;
        });
      })
    .row.border-bottom.pb-2.pt-2.mr-2.ml-2
      .col-4.text-left
        - (Cmpnts + ["top"]).each do |v|
          %a{ :href => "/#{v}" }= v.capitalize
      .col-4.text-center Kubectl Website
      .col-4.text-right
        %a{ :href => "/_cfg" } Config
        %a{ :href => "/_graph" } Graphs
        %a{ :href => "/_ip" } Ip
        %a._busybox{ :href => "/_busybox" } Busybox
        %a{ :href => "/_busybox" } BusyboxNS
    .row.pt-2
      .col-12.text-center= yield

@@ choice
%h1 Pick and Choose
%h2= request.path
- (@choices || YesNo).each do |c|
  %a.btn.btn-primary{ :href => "#{request.path}/#{c.downcase}" }= c

@@ table
:javascript
  $(document).ready(function(){$('#datatable').DataTable({"pageLength": 100});})
%table#datatable.table.table-striped.table-hover
  %thead.thead-dark
    %tr= header_row(@allrows.first)
  %tbody
    - @allrows[1..-1].each_with_index do |row,idx|
      %tr= line_to_row(row,idx)

@@ config
- if ENV['KUBECONFIG']
  %h1= Kubectl.version rescue nil
%form{ :action => "/_cfg", :method => :post }
  %label{ :for => :kubeconfig } KubeConfig
  %input{ :id => :kubeconfig, :type => :text, :value => Kubectl.kbcfg, :size => 80, :name => :kubeconfig }
  %input.btn.btn-success{ :type => :submit, :value => "Update" }
  %a.btn.btn-warning{ :href => "/" } Cancel

@@ scale
%form{ :action => request.path, :method => :post }
  %h1= "Rescaling #{params[:ns]}.#{params[:name]}"
  %label{ :for => :scale } Scale
  %input#scale{ :type => :number, :value => @scale, :name => :scale }
  %input.btn.btn-success{ :type => :submit, :value => "Update" }
  %a.btn.btn-warning{ :href => "/#{request.path.split(/\//)[1]}" } Cancel

@@ graph
.container-fluid
  .row
    .col-12
      #cpugraph
  .row
    .col-12
      #memgraph
:javascript
  function toggleLegend(chartid) {
    $('#'+chartid).find('g.highcharts-legend-item').click()
    return false;
  }
  function handleClkSeries(chartid,elem,event) {
    var sername = elem.name;
    if ( event.metaKey) {
      $.get("/#{@cmp}/#{@ns}/"+elem.name+"/log").fail(NotApp);
    } else if ( event.altKey ) {
      $.get("/#{@cmp}/#{@ns}/"+elem.name+"/shell").fail(NotApp);
    } else {
      hideSeries(chartid, elem.name);
    }
  }
  function hideSeries(chartid,sername) {
    $($('#'+chartid).find('g.highcharts-legend-item')
      .filter(function(_,e){return $(e).find('text').text() === sername})[0])
      .click();
  }
  var perc = "#{@units}" === "percent";

  $(document).ready(function(){
    var optionsCpu = {
      chart: {
        renderTo: 'cpugraph', plotBackgroundColor: null,
        plotBorderWidth: null, plotShadow: false
      },
      yAxis: {
        title: {
          text: (perc ? "Percent of limit" : 'CPU usage in millicpu')
        }
      },
      xAxis: {
        type: 'datetime',
        title: { text: 'Time' }
      },
      legend: {
          align: 'right',
          verticalAlign: 'middle',
          layout: 'vertical'
      },
      title: {
        text: 'CPU Resources <a href="#" onclick="return toggleLegend(\'cpugraph\')">Toggle</a>',
        useHTML: true
      },
      tooltip: { pointFormat: '{series.name}: <b>{point.y}</b>' },
      plotOptions: {
        series: {
          cursor: 'pointer',
          events: {
            click: function (event) { handleClkSeries('cpugraph',this,event) }
          }
        }
      }
    }

    var optionsMem = {
      chart: {
        renderTo: 'memgraph', plotBackgroundColor: null,
        plotBorderWidth: null, plotShadow: false
      },
      yAxis: {
        title: {
          text: (perc ? "Percent of Limit" : 'Memory in MegaBytes'),
        }
      },
      xAxis: {
        type: 'datetime',
        title: { text: 'Time' }
      },
      legend: {
          align: 'right',
          verticalAlign: 'middle',
          layout: 'vertical'
      },
      title: {
        text: 'Memory Resources <a href="#" onclick="return toggleLegend(\'memgraph\')">Toggle</a>',
        useHTML: true
      },
      tooltip: {
        pointFormat: '{series.name}: <b>{point.y}</b>',
      },
      plotOptions: {
        series: {
          cursor: 'pointer',
          events: {
            click: function (event) { handleClkSeries('memgraph',this,event) }
          }
        }
      }
    }

    window.chartcpu = Highcharts.chart(optionsCpu);
    window.chartmem = Highcharts.chart(optionsMem);

    function updateChart(chart, type) {
      $.get("/_graph.json?t="+type+"&c=#{@cmp}&ns=#{@ns}&u=#{@units}&d=#{@limits}")
        .done(function(data){
          var ts = (new Date()).getTime();
          $.each(data.data, function(idx, dp) {
            var dp_def = false;
            $.each(chart.series, function(idx, series) {
              if ( series.name === dp.name ) {
                series.addPoint([ts,dp.value], true)
                dp_def = true;
              }
            })
            if ( !dp_def ) {
              chart.addSeries({name: dp.name, data: [ [ts,dp.value] ]})
            }
          })
          setTimeout(function(){updateChart(chart,type)},5000);
      })
      .fail(function(){
        setTimeout(function(){updateChart(chart,type)},5000);
      })
    }

    function updateCpuChart() { updateChart(window.chartcpu, "cpu") }
    function updateMemChart() { updateChart(window.chartmem, "mem") }
    updateMemChart()
    updateCpuChart()
  })
