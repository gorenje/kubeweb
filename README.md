# KubeWeb

Simple web interface on top of kubectl. Basically does the same as
the k8s dashboard interface but using the kubectl CLI. This makes
kubeweb faster.

Kubeweb is designed to be run locally since it starts terminal windows
for interacting with k8s cluster.

## Installation

Fairly typical sinatra/ruby project:

    gem install bundler
    bundle
    PORT=5000 foreman start

After that, it's turtles all the way down.

Open the configuration page and enter the location of your kubeconfig file:

    open http://localhost:5000/_cfg

After that, everything should work fine.

## Deployment

None. This is intended to be only run locally.

## Assumptions

You are using a Mac since this uses ```osascript``` to start terminal
windows.

## Motivation

Simple because I found the k8s Dashboard to be super slow, I started to
use the ```kubectl``` CLI but soon got sick of typing lines and lines of
options (```kubectl logs podname-5789977b67-272rq -n namespace --follow=true --kubeconfig="/users/me/downloads/kubeconfig"``` is just one example)
