# Provider

provider "aws" {
    region = "${var.region}"
}

## VPC and Gateway
resource "aws_vpc" "main" {
    cidr_block = "${var.vpc_cidr}"

    tags = {
        Name        = "primary-vpc.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
}

resource "aws_internet_gateway" "main" {
    vpc_id = "${aws_vpc.main.id}"

    tags = {
        Name        = "primary-igw.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
}

## Routes, Subnets, NACL

resource "aws_route_table" "internet" {
    vpc_id = "${aws_vpc.main.id}"
    
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.main.id}"
    }

    tags = {
        Name        = "internet-rt.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
}

data "aws_availability_zones" "available" {
    state = "available"
}

resource "aws_subnet" "web-region-a" {
    vpc_id              = "${aws_vpc.main.id}"
    cidr_block          = cidrsubnet(var.vpc_cidr,4,0)
    availability_zone   = "${data.aws_availability_zones.available.names[0]}"

    tags = {
        Name        = "web-subnet-a.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
}

resource "aws_route_table_association" "internet_web_subnet_a" {
    subnet_id       = "${aws_subnet.web-region-a.id}"
    route_table_id  = "${aws_route_table.internet.id}"
}

resource "aws_network_acl" "main" {
    vpc_id = "${aws_vpc.main.id}"
    subnet_ids = ["${aws_subnet.web-region-a.id}"]

    ingress {
        protocol = -1
        rule_no = 100
        action = "allow"
        cidr_block = "0.0.0.0/0"
        from_port = 0
        to_port = 0
    }

    egress {
        protocol = -1
        rule_no = 100
        action = "allow"
        cidr_block = "0.0.0.0/0"
        from_port = 0
        to_port = 0
    }

    tags = {
        Name        = "primary-nacl.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
}

## EC2 and Security groups

resource "aws_security_group" "web" {
    vpc_id = "${aws_vpc.main.id}"
    
    # Everything out
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Everything in from port 80
    ingress {
        from_port = 80
        to_port = 80
        protocol ="tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
   
    tags = {
        Name        = "web-security-group.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
    
}

# Ubuntu image
data "aws_ami" "ubuntu" {
    most_recent = true
    filter {
        name    = "name"
        values  = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
    }
    filter {
        name    = "virtualization-type"
        values  = ["hvm"]
    }
    owners      = ["099720109477"]
}

resource "aws_instance" "web_instance" {
    ami                         = "${data.aws_ami.ubuntu.id}"
    instance_type               = "t2.micro"
    subnet_id                   = "${aws_subnet.web-region-a.id}"
    associate_public_ip_address = true
    availability_zone           = "${data.aws_availability_zones.available.names[0]}"
    vpc_security_group_ids      = ["${aws_security_group.web.id}"]
    key_name                    = "${var.ssh_key_name}" 
    user_data                   = "${var.web_userdata}"

    tags = {
        Name        = "web-instance.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
}

