# ------------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------------

output "JENKINS_URL" {
  value = "http://${google_compute_forwarding_rule.main.ip_address}:8080"
}