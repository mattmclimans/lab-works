# ------------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------------

output "internal_lb_ip" {
  value = google_compute_forwarding_rule.intlb.ip_address
}