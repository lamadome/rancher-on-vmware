

data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}


data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.vm_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.vm_template
  datacenter_id = data.vsphere_datacenter.dc.id
}



resource "vsphere_virtual_machine" "rke-nodes" {
  count            = var.vm_count
  name             = "${var.vm_prefix}${count.index + 1}"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  num_cpus = var.vm_cpucount
  memory   = var.vm_memory
  guest_id = data.vsphere_virtual_machine.template.guest_id
  firmware = "efi"
  network_interface {
    network_id = data.vsphere_network.network.id
  }

  disk {
    label = "disk0"
    size  = 16
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

  }

  extra_config = {
    "guestinfo.metadata" = base64encode(templatefile("${path.module}/templates/metadata.yml.tpl", {
      node_ip       = "${var.vm_network}${count.index + 111}/${var.vm_netmask}",
      node_gateway  = var.vm_gateway,
      node_dns      = var.vm_dns,
      node_hostname = "${var.vm_prefix}${count.index + 1}"
    }))

    "guestinfo.metadata.encoding" = "base64"

    "guestinfo.userdata" = base64encode(templatefile("${path.module}/templates/userdata.yml.tpl", {
      vm_ssh_user = var.vm_ssh_user,
      vm_ssh_key = var.vm_ssh_key
    }))
    "guestinfo.userdata.encoding" = "base64"
  }
provisioner "remote-exec" {
    inline = [
      "sudo usermod -aG docker ${var.vm_ssh_user}"
    ]

    connection {
      type     = "ssh"
      host     = self.default_ip_address
      user     = var.vm_ssh_user
      private_key = file("~/.ssh/id_rsa")
    }
  }
  
}


resource "vsphere_virtual_machine" "rke-lb" {
  name             = var.lb_prefix
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus = var.lb_cpucount
  memory   = var.lb_memory
  guest_id = data.vsphere_virtual_machine.template.guest_id
  firmware = "efi"
  network_interface {
    network_id = data.vsphere_network.network.id
  }

  disk {
    label = "disk0"
    size  = 20
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  extra_config = {
    "guestinfo.metadata" = base64encode(templatefile("${path.module}/templates/metadata.yml.tpl", {
      node_ip       = "${var.lb_address}/${var.lb_netmask}"
      node_gateway  = var.vm_gateway,
      node_dns      = var.vm_dns,
      node_hostname = var.lb_prefix
    }))

    "guestinfo.metadata.encoding" = "base64"


    "guestinfo.userdata" = base64encode(templatefile("${path.module}/templates/userdata_lb.yml.tpl", {
      servers = vsphere_virtual_machine.rke-nodes.*.default_ip_address,
      vm_ssh_user = var.vm_ssh_user,
      vm_ssh_key = var.vm_ssh_key
    }))
    "guestinfo.userdata.encoding" = "base64"



  }

  provisioner "remote-exec" {
    inline = [
      "sudo rm -f /etc/SUSEConnect",
      "sudo rm -rf /etc/zypp/credentials.d/*",
      "sudo rm -rf /etc/zypp/repos.d/*",
      "sudo rm -f /etc/zypp/services.d/*",
      "sudo SUSEConnect -r ${var.reg_key} -e ${var.reg_email}",
      "sudo zypper refresh && sudo zypper in -y nginx",
      "sudo mv /root/nginx.conf /etc/nginx/nginx.conf",
      "sudo service nginx restart"
    ]

    connection {
      type     = "ssh"
      host     = self.default_ip_address
      user     = var.vm_ssh_user
      private_key = file("~/.ssh/id_rsa")
    }
  }
}