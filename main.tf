provider "aws" {
  region  = "eu-west-3"
  version = "~> 1.36"
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  default     = "8080"
}

variable "lb_port" {
  description = "The port the lb will use for HTTP requests"
  default     = "80"
}

output "public_lb_dns" {
  value = "${aws_lb.example.dns_name}"
}

# Fetched from the provider
data "aws_availability_zones" "all" {}
data "aws_vpc" "selected" {}
data "aws_subnet_ids" "all" {
  vpc_id = "${data.aws_vpc.selected.id}"
}

# LB across all subnets
resource "aws_lb" "example" {
    name = "terraform-alb-example"
    security_groups = ["${aws_security_group.lb.id}"]
    subnets = ["${data.aws_subnet_ids.all.ids}"]
}

# Forward to target group
resource "aws_lb_listener" "example" {
    load_balancer_arn = "${aws_lb.example.arn}"
    port = "80"
    protocol = "HTTP"

    default_action {
      type = "forward"
      target_group_arn = "${aws_lb_target_group.example.arn}"
    }
}

resource "aws_lb_target_group" "example" {
    name     = "terraform-alb-tg-example"
    port     = "${var.server_port}"
    protocol = "HTTP"
    vpc_id   = "${data.aws_vpc.selected.id}"

    health_check {
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout             = 3
      path                = "/"
      interval            = 30
    }
}

resource "aws_autoscaling_group" "example" {
    launch_configuration = "${aws_launch_configuration.example.id}"
    availability_zones   = ["${data.aws_availability_zones.all.names}"]
    target_group_arns    = ["${aws_lb_target_group.example.arn}"]

    min_size = 2
    max_size = 4

    tag {
      key                 = "Name"
      value               = "terraform-asg-example"
      propagate_at_launch = true
    }

}

resource "aws_launch_configuration" "example" {
    image_id        = "ami-06340c8c12baa6a09"
    instance_type   = "t2.micro"
    key_name        = "terraform-key"
    security_groups = ["${aws_security_group.instance.id}"]

    user_data = <<-EOF
                #!bin/bash
                yum install -y httpd
                echo "Online server" > /var/www/html/index.html
                sed 's/Listen 80/Listen "${var.server_port}"/' /etc/httpd/conf/httpd.conf -i
                service httpd start
                EOF

    # Creates a new launch configuration before destoying the former one
    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_security_group" "instance" {
    name = "terraform-example-instance-sg"

    egress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }

    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_security_group_rule" "instance" {
    type        = "ingress"
    from_port   = "${var.server_port}"
    to_port     = "${var.server_port}"
    protocol    = "tcp"
    security_group_id = "${aws_security_group.instance.id}"
    source_security_group_id = "${aws_security_group.lb.id}"
}

resource "aws_security_group" "lb" {
    name = "terraform-example-lb-sg"

    egress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }

    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_security_group_rule" "lb" {
    type        = "ingress"
    from_port   = "${var.lb_port}"
    to_port     = "${var.lb_port}"
    protocol    = "tcp"
    security_group_id = "${aws_security_group.lb.id}"
    cidr_blocks = ["0.0.0.0/0"]
}
