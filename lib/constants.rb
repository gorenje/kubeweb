YesNo  = ["Yes", "No"]
SpcRE  = /[[:space:]]+/
Cmpnts = ["nodes",  "namespaces", "pvc", "deployments", "pods", "services",
          "ingress", "daemonsets"]
MxPler = {:h => 3600, :m => 60, :d => 86400, :Gi => 1024, :Ki => 1/1024.0 }
Nrm    = Proc.new { |v,u| v.to_i * (MxPler[(u||"").to_sym] || 1) }

PidOfForeman = "\\$(pidof 'foreman: master')"
PidLookup = {
  "pushtech" => {
    "website"            => PidOfForeman,
    "notificationserver" => PidOfForeman,
    "imageserver"        => PidOfForeman,
  }
}
