output "ec2_instance_public_ip"{
    value = "${aws_instance.web_instance.public_ip}"
}