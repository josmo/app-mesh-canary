variable "gateway_image" {
  default = "usernames/lum-proxy:appmesh"
}
variable "node_1_image" {
  default = "karthequian/helloworld:latest"
}
variable "node_2_image" {
  default = "tutum/hello-world"
}
variable "namespace" {
  default = "lum.local"
}
variable "mesh_name" {
  default = "luminary-mesh"
}
