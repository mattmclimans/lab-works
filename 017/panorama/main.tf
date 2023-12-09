# ------------------------------------------------------------------------------------
# Create a Panorama Device Group, Template, & Template Stack.
# ------------------------------------------------------------------------------------

# device group
resource "panos_device_group" "main" {
  name        = var.panorama_device_group
  description = "Device group for VM-Series on GCP"
}

# template
resource "panos_panorama_template" "main" {
  name        = var.panorama_template
  description = "Template for VM-Series on GCP"
}

# template stack
resource "panos_panorama_template_stack" "main" {
  name        = var.panorama_template_stack
  description = "Template stack for VM-Series on GCP"
  templates   = [panos_panorama_template_stack.main.id]
}



# ------------------------------------------------------------------------------------
# Create eth1/1 & eth1/2 within the Template.
# ------------------------------------------------------------------------------------

# eth1/1 (untrust)
resource "panos_panorama_ethernet_interface" "eth1" {
  name                      = "ethernet1/1"
  template                  = panos_panorama_template_stack.main.name
  mode                      = "layer3"
  enable_dhcp               = true
  create_dhcp_default_route = true
}

# eth1/2 (trust)
resource "panos_panorama_ethernet_interface" "eth2" {
  name                      = "ethernet1/2"
  template                  = panos_panorama_template_stack.main.name
  mode                      = "layer3"
  enable_dhcp               = true
  create_dhcp_default_route = false
}


# ------------------------------------------------------------------------------------
# Create zones within the Template Stack.
# ------------------------------------------------------------------------------------

# untrust zone (eth1/1)
resource "panos_zone" "untrust" {
  name     = "untrust"
  template = panos_panorama_template_stack.main.name
  mode     = "layer3"
  interfaces = [
    panos_panorama_ethernet_interface.eth1.name
  ]
}

# trust zone (eth1/2)
resource "panos_zone" "trust" {
  name     = "trust"
  template = panos_panorama_template_stack.main.name
  mode     = "layer3"
  interfaces = [
    panos_panorama_ethernet_interface.eth2.name
  ]
}

# create a tag to color code the untrust zone
resource "panos_panorama_administrative_tag" "untrust" {
  name         = "untrust"
  device_group = var.panorama_device_group
  color        = "color6"
  depends_on = [
    panos_zone.untrust
  ]
}


# create a tag to color code the trust zone
resource "panos_panorama_administrative_tag" "trust" {
  name         = "trust"
  device_group = var.panorama_device_group
  color        = "color13"
  depends_on = [
    panos_zone.trust
  ]
}


# ------------------------------------------------------------------------------------
# Create virtual router & static routes inside the template.
# ------------------------------------------------------------------------------------

# virtual router
resource "panos_virtual_router" "main" {
  name     = "gcp-vr"
  template = panos_panorama_template_stack.main.name

  interfaces = [
    panos_panorama_ethernet_interface.eth1.name,
    panos_panorama_ethernet_interface.eth2.name,
  ]
}

# rfc1918 route
resource "panos_panorama_static_route_ipv4" "route1" {
  template       = panos_panorama_template_stack.main.name
  virtual_router = panos_virtual_router.main.name
  name           = "rfc-a"
  destination    = "10.0.0.0/8"
  interface      = panos_panorama_ethernet_interface.eth2.name
  next_hop       = var.trust_subnet_gateway
}

# rfc1918 route
resource "panos_panorama_static_route_ipv4" "route2" {
  template       = panos_panorama_template_stack.main.name
  virtual_router = panos_virtual_router.main.name
  name           = "rfc-b"
  destination    = "172.16.0.0/12"
  interface      = panos_panorama_ethernet_interface.eth2.name
  next_hop       = var.trust_subnet_gateway
}

# rfc1918 route
resource "panos_panorama_static_route_ipv4" "route3" {
  template       = panos_panorama_template_stack.main.name
  virtual_router = panos_virtual_router.main.name
  name           = "rfc-c"
  destination    = "192.168.0.0/16"
  interface      = panos_panorama_ethernet_interface.eth2.name
  next_hop       = var.trust_subnet_gateway
}


# ------------------------------------------------------------------------------------
# Create NAT policy translate outbound internet traffic through untrust NIC.
# ------------------------------------------------------------------------------------

resource "panos_panorama_nat_rule_group" "outbound" {
  provider         = panos
  position_keyword = "bottom"
  device_group     = panos_device_group.main.name

  rule {
    name = "outbound"
    original_packet {
      source_zones          = ["trust"]
      destination_zone      = "untrust"
      destination_interface = "any"
      service               = "any"
      source_addresses      = ["any"]
      destination_addresses = ["any"]
    }

    translated_packet {
      source {
        dynamic_ip_and_port {
          interface_address {
            interface = "ethernet1/1"
          }
        }
      }
      destination {}
    }
  }
}



# ------------------------------------------------------------------------------------
# Create Load Balancer Health Check Config: NAT, mgmt profile, & loopback.
# ------------------------------------------------------------------------------------

# create a tag to color code health-check objects.
resource "panos_panorama_administrative_tag" "healthcheck" {
  name         = "healh-checks"
  color        = "color15"
  device_group = var.panorama_device_group
}

# address group for LB health-check range 1
resource "panos_address_object" "healthcheck1" {
  name         = "health-check-1"
  value        = "35.191.0.0/16"
  device_group = var.panorama_device_group

  tags = [
    panos_panorama_administrative_tag.healthcheck.name
  ]
}

# address group for LB health-check range 2
resource "panos_address_object" "healthcheck2" {
  name         = "health-check-2"
  value        = "130.211.0.0/22"
  device_group = var.panorama_device_group

  tags = [
    panos_panorama_administrative_tag.healthcheck.name
  ]
}

# create address group for both health-check ranges
resource "panos_panorama_address_group" "healthcheck" {
  name         = "health-checks"
  device_group = var.panorama_device_group
  description  = "GCP load balancer health check ranges"

  static_addresses = [
    panos_address_object.healthcheck1.name,
    panos_address_object.healthcheck2.name,
  ]

  tags = [
    panos_panorama_administrative_tag.healthcheck.name
  ]
}

# health-check route 1
resource "panos_panorama_static_route_ipv4" "healthcheck1" {
  template       = panos_panorama_template_stack.main.name
  virtual_router = panos_virtual_router.main.name
  name           = "health-check1"
  destination    = "35.191.0.0/16"
  interface      = panos_panorama_ethernet_interface.eth2.name
  next_hop       = var.trust_subnet_gateway
}


# health-check route 2
resource "panos_panorama_static_route_ipv4" "healthcheck2" {
  template       = panos_panorama_template_stack.main.name
  virtual_router = panos_virtual_router.main.name
  name           = "health-check2"
  destination    = "130.211.0.0/22"
  interface      = panos_panorama_ethernet_interface.eth2.name
  next_hop       = var.trust_subnet_gateway
}


# mgmt profile to respond to health checks
resource "panos_panorama_management_profile" "healthcheck" {
  template = panos_panorama_template_stack.main.name
  name     = "health-checks"
  ping     = true
  http     = true
}

# loopback with mgmt profile assigned
resource "panos_panorama_loopback_interface" "healthcheck" {
  name               = "loopback.1"
  template           = panos_panorama_template_stack.main.name
  comment            = "Loopback for load balancer health checks"
  static_ips         = [var.loopback_ip]
  management_profile = panos_panorama_management_profile.healthcheck.name
}

# healthcheck zone
resource "panos_zone" "healthcheck" {
  name     = "healthcheck"
  template = panos_panorama_template_stack.main.name
  mode     = "layer3"
  interfaces = [
    panos_panorama_loopback_interface.healthcheck.name
  ]
}

# NAT rule to send healthchecks to loopback
resource "panos_panorama_nat_rule_group" "main" {
  provider         = panos
  position_keyword = "top"
  device_group     = panos_device_group.main.name

  rule {
    name = "health-checks"
    original_packet {
      source_zones          = ["trust"]
      destination_zone      = "trust"
      destination_interface = "ethernet1/2"
      service               = "any"
      source_addresses      = ["35.191.0.0/16", "130.211.0.0/22"]
      destination_addresses = ["any"]
    }

    translated_packet {
      source {}
      destination {
        dynamic_translation {
          address = var.loopback_ip
        }
      }
    }
  }
}

# ------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------
