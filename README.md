# Sample terraform project for creating a VPC, with ECS/App mesh/X-Ray

## About
### layout
[api](api) -> has the container definition, ecs service and service discovery
[ec2-ecs](ec2-ecs) -> commented out in main but template for creating the public/private instances to join the cluster


* right now it creates 

1. api.{namespace}
2. gateway.{namespace} ->with  api.{namespace} backend
3. api-2.{namespace} ->
4. route for api to api and api-2

### Configurations
* gateway_image -> proxy image needs to point to api
* node_1_image -> api image
* node_2_image -> api-2 image
* namespace -> namespace for service discovery
* mesh_name ->


### GET started
1. clone
2. set aws key and secret env vars
3. terraform.tfvars with whatever variables changes
4. terraform apply