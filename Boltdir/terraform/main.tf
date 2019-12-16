# GCP Project ID
variable "project"        { }
# Domain name assigned to DNS zone
variable "dns_domain"     { }
# Name of of the actual zone in GCP CloudDNS
variable "dns_zone"       { }
# Shared user name across instances
variable "user"           { }
# Location on disk of the SSH key to use for Linux system access
variable "ssh_key"        { default = "~/.ssh/id_rsa.pub" }
# GCP region for the deployment
variable "region"         { default = "us-west1" }
# GCP zones for the deployment
variable "zones"          { default = [ "us-west1-a", "us-west1-b", "us-west1-c" ] }
# Number of compilers to deploy, will be spread across all defined zones
variable "compiler_count" { default = 3 }
# Number of agents to deploy, will be spread across all defined zones
variable "agent_count"    { default = 3 }
# The image deploy Linux with
variable "linux_image"    { default = "centos-cloud/centos-7" }
# Permitted IP subnets, default is internal only, single IP adresses should be defined as /32
variable "firewall_allow" { default = [ "10.128.0.0/9" ] }

provider "google" {
  project = var.project
  region  = var.region
}

# It is intended that multiple deployments can be launched easily without
# name colliding
resource "random_id" "deployment" {
  byte_length = 3
}

# Contain all the networking configuration in a module for readability
module "networking" {
  source = "./modules/networking"
  id     = random_id.deployment.hex
  allow  = var.firewall_allow
}

# Contain all the loadbalancer configuration in a module for readability
module "loadbalancer" {
  source     = "./modules/loadbalancer"
  id         = random_id.deployment.hex
  ports      = ["8140", "8142"]
  network    = module.networking.network_link
  subnetwork = module.networking.subnetwork_link
  region     = var.region
  zones      = var.zones 
  instances  = google_compute_instance.compiler[*]
}

# Create a friendly DNS name for accessing the new PE console external to GCP
# networking
resource "google_dns_record_set" "pe" {
  name = "pe-${random_id.deployment.hex}.${var.dns_domain}."
  type = "A"
  ttl  = 1

  managed_zone = var.dns_zone

  rrdatas = ["${google_compute_instance.master[0].network_interface[0].access_config[0].nat_ip}"]
}

# Create a friendly DNS name for accessing the compiler load balancer's internal
# IP address
resource "google_dns_record_set" "compilers" {
  name = "pe-compilers-${random_id.deployment.hex}.${var.dns_domain}."
  type = "A"
  ttl  = 1

  managed_zone = var.dns_zone

  rrdatas = ["${module.loadbalancer.lb_ip}"]
}

# Instances to run PE MOM
resource "google_compute_instance" "master" {
  name         = "pe-master-${random_id.deployment.hex}-${count.index}"
  machine_type = "n1-standard-4"
  count        = 2
  zone         = element(var.zones, count.index)

  # Old style internal DNS easiest until Bolt inventory dynamic
  metadata = {
    "sshKeys" = "${var.user}:${file(var.ssh_key)}"
    "VmDnsSetting" = "GlobalOnly"
  }

  boot_disk {
    initialize_params {
      image = var.linux_image
      size  = 50
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = module.networking.network_link
    subnetwork = module.networking.subnetwork_link
    access_config { }
  }

  # Using remote-execs on each instance deployemnt to ensure things are really
  # really up before doing to the next step, helps with Bolt plans that'll
  # immediately connect then fail
  provisioner "remote-exec" {
    connection {
      host = self.network_interface[0].access_config[0].nat_ip
      type = "ssh"
      user = var.user
    }
    inline = ["# Connected"]
  }
}

# Instances to run PE PSQL
resource "google_compute_instance" "psql" {
  name         = "pe-psql-${random_id.deployment.hex}-${count.index}"
  machine_type = "n1-standard-8"
  count        = 2
  zone         = element(var.zones, count.index)

  # Old style internal DNS easiest until Bolt inventory dynamic
  metadata = {
    "sshKeys" = "${var.user}:${file(var.ssh_key)}"
    "VmDnsSetting" = "GlobalOnly"
  }

  boot_disk {
    initialize_params {
      image = var.linux_image
      size  = 100
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = module.networking.network_link
    subnetwork = module.networking.subnetwork_link
    access_config { }
  }

  # Using remote-execs on each instance deployemnt to ensure things are really
  # really up before doing to the next step, helps with Bolt plans that'll
  # immediately connect then fail
  provisioner "remote-exec" {
    connection {
      host = self.network_interface[0].access_config[0].nat_ip
      type = "ssh"
      user = var.user
    }
    inline = ["# Connected"]
  }
}

# Instances to run a compilers
resource "google_compute_instance" "compiler" {
  name         = "pe-compiler-${random_id.deployment.hex}-${count.index}"
  machine_type = "n1-standard-2"
  count        = var.compiler_count
  zone         = element(var.zones, count.index)

  # Old style internal DNS easiest until Bolt inventory dynamic
  metadata = {
    "sshKeys" = "${var.user}:${file(var.ssh_key)}"
    "VmDnsSetting" = "GlobalOnly"
  }

  boot_disk {
    initialize_params {
      image = var.linux_image
      size  = 15
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = module.networking.network_link
    subnetwork = module.networking.subnetwork_link
    access_config { }
  }

  # Using remote-execs on each instance deployemnt to ensure things are really
  # really up before doing to the next step, helps with Bolt plans that'll
  # immediately connect then fail
  provisioner "remote-exec" {
    connection {
      host = self.network_interface[0].access_config[0].nat_ip
      type = "ssh"
      user = var.user
    }
    inline = ["# Connected"]
  }
}

# Instances to run as agents
resource "google_compute_instance" "agent" {
  name         = "pe-agent-${random_id.deployment.hex}-${count.index}"
  machine_type = "n1-standard-1"
  count        = var.agent_count
  zone         = element(var.zones, count.index)

  # Old style internal DNS easiest until Bolt inventory dynamic
  metadata = {
    "sshKeys" = "${var.user}:${file(var.ssh_key)}"
    "VmDnsSetting" = "GlobalOnly"
  }

  boot_disk {
    initialize_params {
      image = var.linux_image
      size  = 15
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = module.networking.network_link
    subnetwork = module.networking.subnetwork_link
    access_config { }
  }

  # Using remote-execs on each instance deployemnt to ensure thing are really
  # really up before doing the next steps, helps with development tasks that
  # immediately attempt to leverage Bolt
  provisioner "remote-exec" {
    connection {
      host = self.network_interface[0].access_config[0].nat_ip
      type = "ssh"
      user = var.user
    }
    inline = ["# Connected"]
  }
}

# Convient log message at end of Terraform apply to inform you where your
# Splunk instance can be accessed.
output "console" {
  value       = google_dns_record_set.pe.name
  description = "The FQDN of a new Pupept Enterprise console"
}
output "pool" {
  value       = google_dns_record_set.compilers.name
  description = "The FQDN of a new Pupept Enterprise compiler pool"
}
output "infrastructure" {
  value = { 
    masters   : [for i in google_compute_instance.master[*]   : [ "${i.name}.c.${i.project}.internal", i.network_interface[0].access_config[0].nat_ip] ], 
    psql      : [for i in google_compute_instance.psql[*]     : [ "${i.name}.c.${i.project}.internal", i.network_interface[0].access_config[0].nat_ip] ], 
    compilers : [for i in google_compute_instance.compiler[*] : [ "${i.name}.c.${i.project}.internal", i.network_interface[0].access_config[0].nat_ip] ] 
  }
}
output "agents" {
  value = [for i in google_compute_instance.agent[*] : [ "${i.name}.c.${i.project}.internal", i.network_interface[0].access_config[0].nat_ip] ]
}
