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
        cidr_block  = "0.0.0.0/0"
        gateway_id  = "${aws_internet_gateway.main.id}"
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

resource "aws_subnet" "web_region_a" {
    vpc_id              = "${aws_vpc.main.id}"
    cidr_block          = cidrsubnet(var.vpc_cidr,4,0)
    availability_zone   = "${data.aws_availability_zones.available.names[0]}"

    tags = {
        Name        = "web-subnet-a.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
}

resource "aws_subnet" "web_region_b" {
    vpc_id              = "${aws_vpc.main.id}"
    cidr_block          = cidrsubnet(var.vpc_cidr,4,1)
    availability_zone   = "${data.aws_availability_zones.available.names[1]}"

    tags = {
        Name        = "web-subnet-b.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
}


resource "aws_route_table_association" "internet_web_subnet_a" {
    subnet_id       = "${aws_subnet.web_region_a.id}"
    route_table_id  = "${aws_route_table.internet.id}"
}

resource "aws_route_table_association" "internet_web_subnet_b" {
    subnet_id       = "${aws_subnet.web_region_b.id}"
    route_table_id  = "${aws_route_table.internet.id}"
}

resource "aws_network_acl" "main" {
    vpc_id      = "${aws_vpc.main.id}"
    subnet_ids  = ["${aws_subnet.web_region_a.id}"]

    ingress {
        protocol    = -1
        rule_no     = 100
        action      = "allow"
        cidr_block  = "0.0.0.0/0"
        from_port   = 0
        to_port     = 0
    }

    egress {
        protocol    = -1
        rule_no     = 100
        action      = "allow"
        cidr_block  = "0.0.0.0/0"
        from_port   = 0
        to_port     = 0
    }

    tags = {
        Name        = "primary-nacl.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
}

## Loadbalancing (with Security Group)

resource "aws_alb" "web" {
    internal            = false
    load_balancer_type  = "application"
    security_groups     = ["${aws_security_group.http_from_anywhere.id}"]
    subnets             = ["${aws_subnet.web_region_a.id}","${aws_subnet.web_region_b.id}"]

    tags = {
        Name        = "web-lb.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
}

resource "aws_security_group" "http_from_anywhere" {
    vpc_id = "${aws_vpc.main.id}"
    
    # Everything out to anywhere
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Port 80 from anywhere
    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
   
    tags = {
        Name        = "http-from-anywhere-security-group.${var.environment}.${var.project}"
        Project     = "${var.project}"
        Environment = "${var.environment}"
    }
    
}

resource "aws_alb_listener" "web_alb_listener" {
    load_balancer_arn   = "${aws_alb.web.arn}"
    port                = "80"
    protocol            = "HTTP"

    default_action{
        type                = "forward"
        target_group_arn    = "${aws_alb_target_group.web_instance_tg.arn}"
    }
}

resource "aws_alb_target_group" "web_instance_tg" {
    name        = "web-tg"
    port        = "80"
    protocol    = "HTTP"
    vpc_id      = "${aws_vpc.main.id}"
}

## Launch Template, Autoscaling and ASG security groups

resource "aws_security_group" "http_from_lb" {
    vpc_id = "${aws_vpc.main.id}"
    
    # Everything out to anywhere
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Port 80 from LB security group
    ingress {
        from_port       = 80
        to_port         = 80
        protocol        = "tcp"
        security_groups = ["${aws_security_group.http_from_anywhere.id}"]
    }
   
    tags = {
        Name        = "http-from-lb-security-group.${var.environment}.${var.project}"
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

resource "aws_launch_template" "web_launch_template" {
    name                                    = "web-instance-launch-template.${var.environment}.${var.project}"
    description                             = "launch template for web instances"
    image_id                                = "${data.aws_ami.ubuntu.id}"
    instance_type                           = "t2.micro"
    instance_initiated_shutdown_behavior    = "terminate"
    key_name                                = "${var.ssh_key_name}"
    user_data                               = "${base64encode(var.web_userdata)}"

    network_interfaces {
        associate_public_ip_address = true
        security_groups             = ["${aws_security_group.http_from_lb.id}"]
        delete_on_termination       = true
    }

    tag_specifications {
        resource_type = "instance"
        tags = {
            Name        = "web-instance.${var.environment}.${var.project}"
            Project     = "${var.project}"
            Environment = "${var.environment}"
        }
    }  
}

resource "aws_autoscaling_group" "web_autoscaling_group" {
    name                = "web-asg.${var.environment}.${var.project}"
    desired_capacity    = 1
    max_size            = 1
    min_size            = 1
    vpc_zone_identifier = ["${aws_subnet.web_region_a.id}","${aws_subnet.web_region_b.id}"]

    launch_template {
        id  = "${aws_launch_template.web_launch_template.id}"
        version = "$Latest"
    }

    tag {
        key                 = "Project"
        value               = "${var.project}"
        propagate_at_launch = false
    }
    
    tag {
        key                 = "Environment"
        value               = "${var.environment}"
        propagate_at_launch = false
    }
}

resource "aws_autoscaling_attachment" "web_autoscaling_attachment" {
    autoscaling_group_name  = "${aws_autoscaling_group.web_autoscaling_group.id}"
    alb_target_group_arn    = "${aws_alb_target_group.web_instance_tg.arn}"
}