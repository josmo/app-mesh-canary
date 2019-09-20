data "template_file" "container_definitions" {
  template = file("${path.module}/templates/container_definitions.json")
  vars = {
    image = var.image
    log_name = var.log_name
    name = var.name
    mesh_name = var.mesh
    mesh_node = var.mesh_node
  }
}