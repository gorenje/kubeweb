require 'json'

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
    case cmp
    when "namespaces"
      kctl("delete #{cmp.to_s} --force #{ns}")
    else
      kctl("delete #{cmp.to_s} -n #{ns} --force #{name}")
    end
  end

  def top(cmp, ns = nil)
    kctl("top #{cmp} " +
         (cmp == "pods" ? ((ns ? "-n #{ns}" : "--all-namespaces") +
                           " --containers=true") : ""))
  end

  # Return an array of output lines, similar to what 'kubectl get' returns.
  # Each line becomes an array entry. This implies the first line is
  # the header line and the rest are entries. The header line is split by
  # spaces, which then determines the number of columns in the result table.
  # See views/table.haml for details.
  #
  # Because some components have extra spaces in their header lines, we
  # retrieve these using JSON and convert to a more generic representation.
  def get(cmp)
    case cmp
    when "events"
      hsh = JSON(kctl("get #{cmp.to_s} --all-namespaces --output=json").join)
      header = "NAMESPACE NAME LAST&nbsp;SEEN FIRST&nbsp;SEEN COUNT KIND "+
               "SUBOBJECT TYPE REASON SOURCE MESSAGE"

      [header] +
        (hsh["items"].map do |item|
           obj = item["involvedObject"]
           src = item["source"]
           [ obj["namespace"],
             obj["name"],
             _unitsago(item["lastTimestamp"]),
             _unitsago(item["firstTimestamp"]),
             item["count"],
             obj["kind"],
             obj["fieldPath"],
             item["type"],
             item["reason"],
             "%s, %s" % [src["component"], src["host"]],
             item["message"]
           ].map{ |v| (v || "&nbsp;").to_s.gsub(/[[:space:]+]/, "&nbsp;") }.
             join(" ")
         end)

    when 'nodes'
      hsh = JSON(kctl("get #{cmp.to_s} --all-namespaces --output=json").join)
      header = "NAME STATUS CPU MEMORY KUBELET&nbsp;VERSION " +
               "KERNEL&nbsp;VERSION CONTAINER&nbsp;VERSION ADDRESS AGE"
      [header] +
        (hsh["items"].map do |item|
           md,sp,st,age = _splat(item)
           status = st["conditions"].select { |a| a["status"] == "True" }.
                      map { |a| a["type"] }.join(",")
           ni = st["nodeInfo"]

           [md["name"],
            status,
            st["capacity"]["cpu"],
            st["capacity"]["memory"],
            ni["kubeletVersion"],
            ni["kernelVersion"],
            ni["containerRuntimeVersion"],
            st["addresses"].map { |a| a["address"] }.join(","),
            age,
           ].map{ |v| v || "&nbsp;" }.join(" ")
         end)

    when 'ingress'
      hsh = JSON(kctl("get #{cmp.to_s} --all-namespaces --output=json").join)
      header = "NAMESPACE NAME HOSTS AGE"
      [header] + (hsh["items"].map do |item|
                    md,sp,st,age = _splat(item)
                    [md["namespace"], md["name"],
                     sp["rules"].map{|a|a["host"]}.join(",<br>"),
                     age
                    ].map{ |v| v || "&nbsp;" }.join(" ")
                  end)

    when 'pvc'
      hsh = JSON(kctl("get #{cmp.to_s} --all-namespaces --output=json").join)
      header = "NAMESPACE NAME STATUS VOLUME CAPACITY ACCESS&nbsp;MODES "+
               "STORAGECLASS AGE"
      [header] + (hsh["items"].map do |item|
                    md,sp,st,age = _splat(item)
                    [md["namespace"], md["name"],
                     st["phase"],
                     sp["volumeName"],
                     st["capacity"]["storage"],
                     st["accessModes"].join(","),
                     sp["storageClassName"],
                     age
                    ].map{ |v| v || "&nbsp;" }.join(" ")
                  end)

    when 'pods'
      hsh = JSON(kctl("get #{cmp.to_s} --all-namespaces --output=json").join)
        header = "NAMESPACE NAME READY STATUS RESTARTS AGE IP NODE"
        [header] + (hsh["items"].map do |item|
                      md,sp,st,age = _splat(item)

                      ready,not_ready =
                            begin
                              st["containerStatuses"].partition do |cs|
                                cs["ready"]
                              end
                            rescue NoMethodError
                              [[],[]]
                            end
                      rsc =
                        begin
                          st["containerStatuses"].map do |cs|
                            cs["restartCount"]
                          end.sum
                        rescue NoMethodError
                          0
                        end

                      [md["namespace"], md["name"],
                       "#{ready.size}/#{ready.size + not_ready.size}",
                       st["phase"],
                       rsc,
                       age,
                       st["podIP"],
                       sp["nodeName"],
                      ].map{ |v| v || "&nbsp;" }.join(" ")
                    end)

    when "daemonsets"
      hsh = JSON(kctl("get #{cmp.to_s} --all-namespaces --output=json").join)
      header = "NAMESPACE NAME DESIRED CURRENT READY UP-TO-DATE "+
               "AVAILABLE NODE&nbsp;SELECTOR AGE CONTAINERS IMAGES"
        [header] + (hsh["items"].map do |item|
                      md,sp,st,age = _splat(item)

                      ndselector =
                        (sp["template"]["spec"]["nodeSelector"]||{}).
                          map do |k,v|
                        "#{k}=#{v}"
                      end.join
                      tmp = sp["template"]["spec"]["containers"].map do |c|
                        [c["name"], c["image"]]
                      end
                      images     = tmp.map(&:last).join(",")
                      containers = tmp.map(&:first).join(",")

                      [md["namespace"], md["name"],
                       st["desiredNumberScheduled"],
                       st["currentNumberScheduled"],
                       st["numberReady"],
                       st["updatedNumberScheduled"] || "0",
                       st["numberAvailable"] || "0",
                       ndselector.empty? ? nil : ndselector,
                       age,
                       containers,
                       images,
                      ].map{ |v| v || "&nbsp;" }.join(" ")
                    end)

    else
      kctl("get #{cmp.to_s} --all-namespaces --output=wide")
    end
  end

  def deployment(ns,name)
    kctl("get deployments -n #{ns} #{name}")
  end

  def version
    d = JSON(kctl("version --output=json").join) ; v = 'Version'
    ["client","server"].map { |a| "#{a}: #{d[a+v]['git'+v]}" }.join(" & ")
  end

  def open_terminal(script)
    system("osascript -e 'tell application \"Terminal\" to do script " +
           "\"kubectl #{script} --kubeconfig=\\\"#{kbcfg}\\\"\"'")
  end

  def busybox(ns = nil)
    open_terminal("run -it busybox-#{(rand*1000000).to_i.to_s(16)} " +
                  "-n #{ns || 'default'} --image=busybox --restart=Never")
  end

  def watch(ns,name)
    open_terminal("logs #{_c(ns,name)} --follow=true")
  end

  def shell(ns,name)
    open_terminal("exec #{_c(ns,name)} -it /bin/bash")
  end

  def edit(ns,cmp,name)
    open_terminal("edit #{cmp} #{_c(ns,name)}")
  end

  def describe(ns,cmp,name)
    open_terminal("describe #{cmp} #{_c(ns,name)}")
  end

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

  # Add reference to a container if a pod has multiple containers.
  def _c(ns,name)
    name,container = name =~ /:/ ? name.split(/:/) : [name,nil]
    "#{name} #{container ? '-c ' + container : ''} #{ns ? '-n ' + ns : ''}"
  end

  def _splat(item)
    md,sp,st = ["metadata","spec","status"].map { |a| item[a] }
    [md,sp,st, _unitsago(md["creationTimestamp"])]
  end

  def _unitsago(str)
    case age_seconds = (Time.now - Time.parse(str)).to_i
    when 0..59       then "#{age_seconds}s"
    when 60..3599    then "#{age_seconds / 60}m"
    when 3600..86399 then "#{age_seconds / 3600}h"
    else "#{age_seconds / 86400}d"
    end
  end
end
