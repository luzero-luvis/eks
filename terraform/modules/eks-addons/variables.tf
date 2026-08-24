variable "cluster_name" {
  description = "Cluster the add-ons are installed into"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version used to resolve compatible add-on versions"
  type        = string
}

variable "addons" {
  description = "Add-ons to install, keyed by add-on name (e.g. vpc-cni, coredns)"
  type = map(object({
    name                     = optional(string) # falls back to the map key
    most_recent              = optional(bool, true)
    addon_version            = optional(string)
    configuration_values     = optional(string)
    service_account_role_arn = optional(string)
    pod_identity_association = optional(list(object({
      role_arn        = string
      service_account = string
    })))
    preserve                    = optional(bool, true)
    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "PRESERVE")
    timeouts = optional(object({
      create = optional(string)
      update = optional(string)
      delete = optional(string)
    }), {})
    tags = optional(map(string), {})
  }))
  default  = {}
  nullable = false
}

variable "tags" {
  description = "Tags applied to every add-on"
  type        = map(string)
  default     = {}
}
