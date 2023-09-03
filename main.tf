terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "tf-azure-rg" {
  name     = "temp-infra-resources"
  location = "UK South"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "tf-vn" {
  name                = "demo-network"
  resource_group_name = azurerm_resource_group.tf-azure-rg.name
  location            = azurerm_resource_group.tf-azure-rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "tf-subnet" {
  name                 = "demo-subnet"
  resource_group_name  = azurerm_resource_group.tf-azure-rg.name
  virtual_network_name = azurerm_virtual_network.tf-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "tf-sec-group" {
  name                = "demo-sec-grp"
  location            = azurerm_resource_group.tf-azure-rg.location
  resource_group_name = azurerm_resource_group.tf-azure-rg.name

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "tf-dev-rule" {
  name                        = "demo-dev-rule-1"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "93.186.159.159/32"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf-azure-rg.name
  network_security_group_name = azurerm_network_security_group.tf-sec-group.name
}

resource "azurerm_subnet_network_security_group_association" "tf-sec-assoc" {
  subnet_id                 = azurerm_subnet.tf-subnet.id
  network_security_group_id = azurerm_network_security_group.tf-sec-group.id
}

resource "azurerm_public_ip" "tf-public-ip" {
  name                = "DevPublicIp1"
  resource_group_name = azurerm_resource_group.tf-azure-rg.name
  location            = azurerm_resource_group.tf-azure-rg.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "tf-dev-vm-nic" {
  name                = "dev-vm-nic"
  location            = azurerm_resource_group.tf-azure-rg.location
  resource_group_name = azurerm_resource_group.tf-azure-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.tf-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.tf-public-ip.id
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "tf-linux-vm" {
  name                  = "dev-vm"
  resource_group_name   = azurerm_resource_group.tf-azure-rg.name
  location              = azurerm_resource_group.tf-azure-rg.location
  size                  = "Standard_B1s"
  admin_username        = "adminuser1"
  network_interface_ids = [azurerm_network_interface.tf-dev-vm-nic.id]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser1"
    public_key = file("~/.ssh/azuredemokey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser1",
      identityfile = "~/.ssh/azuredemokey"
    })
    interpreter = var.host_os == "windows" ? ["Powershell", "-Command"] : ["bash", "-c"]
    
  }

  tags = {
    environment = "dev"
  }
}

data "azurerm_public_ip" "tf-ip-data" {
  name                = azurerm_public_ip.tf-public-ip.name
  resource_group_name = azurerm_resource_group.tf-azure-rg.name
}

output "public_ip_address" {
  value = "${azurerm_linux_virtual_machine.tf-linux-vm.name}: ${data.azurerm_public_ip.tf-ip-data.ip_address}"
}