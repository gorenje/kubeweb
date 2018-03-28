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
    kctl("delete #{cmp.to_s} -n #{ns} --force #{name}")
  end

  def top(cmp, ns = nil)
    kctl("top #{cmp} " +
         (cmp == "pods" ? ((ns ? "-n #{ns}" : "--all-namespaces") +
                           " --containers=true") : ""))
  end

  def get(cmp)
    case cmp
    when 'pvc'
      hsh = JSON(kctl("get #{cmp.to_s} --all-namespaces --output=json").join)
      header = "NAMESPACE NAME STATUS VOLUME CAPACITY ACCESS&nbsp;MODES "+
               "STORAGECLASS"
      [header] + (hsh["items"].map do |item|
                    [item["metadata"]["namespace"],
                     item["metadata"]["name"],
                     item["status"]["phase"],
                     item["spec"]["volumeName"],
                     item["status"]["capacity"]["storage"],
                     item["status"]["accessModes"].join(","),
                     item["spec"]["storageClassName"],
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

  def osascript(script)
    system("osascript -e 'tell application \"Terminal\" to do script " +
           "\"kubectl #{script} --kubeconfig=\\\"#{kbcfg}\\\"\"'")
  end

  def busybox(ns = nil)
    osascript("run -it busybox-#{(rand*1000000).to_i.to_s(16)} " +
              "-n #{ns || 'default'} --image=busybox --restart=Never")
  end

  def watch(ns,name)
    osascript("logs #{_c(ns,name)} --follow=true")
  end

  def shell(ns,name)
    osascript("exec #{_c(ns,name)} -it /bin/bash")
  end

  def describe(ns,cmp,name)
    osascript("describe #{cmp} #{_c(ns,name)}")
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

  def _c(ns,name)
    name,container = name =~ /:/ ? name.split(/:/) : [name,nil]
    "#{name} #{container ? '-c ' + container : ''} -n #{ns}"
  end
end
