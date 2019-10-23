variable "gateway_image" {
  default = "josmo/sample-proxy:lum"
}
variable "node_1_image" {
  default = "karthequian/helloworld:latest"
}
variable "node_2_image" {
  default = "tutum/hello-world"
}
variable "namespace" {
  default = "luminary.local"
}
variable "mesh_name" {
  default = "luminary-mesh"
}