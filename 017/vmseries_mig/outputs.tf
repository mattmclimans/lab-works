# ------------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------------

output "ext_lb_ip" {
  value = google_compute_address.external_nat_ip.address
}