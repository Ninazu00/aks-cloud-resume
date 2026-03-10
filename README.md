# Cloud-resume
My own azure resume

## First, creating digital portfolio and testing containers

- simple frontend using HTML, CSS, and Javascript
- node.js container used for backend server
- nginx used as load balancer
- testing locally with docker-compose for node.js containers and nginx as a proxy
- testing Postgre SQL database and tested locally using docker-compose
## Second, creating kubernetes manifests and testing it locally on minikube
-creating deployment for backend node.js pods
-creating statefulset for Postgre SQL database pods to ensure data persistance
-creating service for backend deployment
-creating service for PostGRE SQL statefule set
-creating ingress to allow external requests into the cluster, forwarding them to backend service
