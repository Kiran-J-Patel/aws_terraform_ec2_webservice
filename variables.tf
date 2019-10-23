variable "region" {
    default = "eu-west-2"
}

variable "project" {
    default = "Example"
}

variable "environment" {
    default = "example"
}

variable "vpc_cidr" {
    default = "172.16.0.0/24"
}

variable "ssh_key_name" {
    type = "string"
    default = "centos-base"
}

variable "web_userdata" {
    default = <<-EOF
        #!/bin/bash
        sudo apt update -y
        sudo apt install apache2 -y
        sudo service apache2 start
        sudo echo "hello automatic cloud" >> /var/www/html/index.html
    EOF
}