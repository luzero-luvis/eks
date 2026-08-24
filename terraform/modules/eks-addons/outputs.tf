output "addons" {
  description = "Installed add-ons keyed by add-on name"
  value       = aws_eks_addon.this
}

output "addon_versions" {
  description = "Resolved version of each installed add-on"
  value       = { for k, v in aws_eks_addon.this : k => v.addon_version }
}
