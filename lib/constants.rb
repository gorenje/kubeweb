YesNo  = ["Yes", "No"]
SpcRE  = /[[:space:]]+/
Cmpnts = ["nodes", "deployments", "pods", "services", "ingress", "pvc"]
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
