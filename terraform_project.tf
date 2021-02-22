#create vpc
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames=true
}
provider "aws" {
  region     = "us-east-2"
  access_key = "AKIAIPISK75DKNPSML2Q"
  secret_key = "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"
  endpoints {
sts = "https://sts.eu-east-2.amazonaws.com"
}

}
#internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "gw"
  }
}

#configure subnet 1
resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "public_subnet"
  }
}
#Associate subnet with RT
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.route1.id
}
resource "aws_route_table" "route1" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}
#subnet 2
resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name = "private_subnet"
  }
}

#Associate subnet with RT
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.route2.id
}

resource "aws_route_table" "route2" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    #network_interface_id=aws_network_interface.NF.id
    gateway_id = aws_internet_gateway.gw.id
  }
}



#security group
resource "aws_security_group" "public_SG" {
  name        = "public_SG"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.vpc.id

ingress {
    description = "all traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  tags = {
    Name = "public_SG"
  }
}
#security group
resource "aws_security_group" "private_SG" {
  name        = "nat_SG"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.vpc.id

ingress {
    description = "mysql"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 


  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    ingress {
    description = "https"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  tags = {name="private_SG"
  }
}



#network_interface
resource "aws_network_interface" "NF" {
  subnet_id      = aws_subnet.public_subnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.public_SG.id]
}
resource "aws_network_interface" "NF2" {
  subnet_id      = aws_subnet.private_subnet.id
  private_ips     = ["10.0.2.50"]
  security_groups = [aws_security_group.private_SG.id]
}


#elastic ip
resource "aws_eip" "one" {
  
  vpc                        = true
  associate_with_private_ip  = "10.0.1.50"
  public_ipv4_pool           = "amazon"
  depends_on                 = [aws_internet_gateway.gw]
}




resource "aws_elb" "ASG" {
  name               = "classicload"
  subnets            =[
    aws_subnet.public_subnet.id,
    aws_subnet.private_subnet.id
    ]
  security_groups    =[
    aws_security_group.public_SG.id
    ]
  cross_zone_load_balancing   = true

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  

  health_check {
    target              = "TCP:80"
    healthy_threshold   = 10
    unhealthy_threshold = 2
    timeout             = 5
    
    interval            = 30
  }

  tags = {
    Name = "classic_lb"
  }
}
resource "aws_lb_target_group" "ASG" {
  name        = "TG"
  port        = 80
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.vpc.id
  health_check{
    protocol="TCP" 
    
  }
}


 
 


resource "aws_launch_template" "agent" {
    name_prefix = "agent-lc-"
    image_id = "ami-02aa7f3de34db391a"#--->ubuntu 18.01
    #ami-0e06fa29a08d84162-->wordpress
    #ami-0a91cd140a1fc148a-->ubuntu
    #ami-0f052119b3c7e61d1-->suse
    #ami-01aab85a5e4a5a0fe-->amazon linux 2
    
    instance_type = "t2.micro"
    key_name="main"
    
    
    
  network_interfaces{
          associate_public_ip_address ="true"
          
          device_index = 0
          security_groups=[aws_security_group.public_SG.id]
          subnet_id      = aws_subnet.public_subnet.id
          delete_on_termination ="true"
          
          
          }/*  user_data = base64encode(<<-EOF
              #!/bin/bash
             sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
             sudo yum install -y httpd mariadb-server  
             sudo systemctl start httpd
             cd /etc/httpd/conf.d
             sudo wget "https://drive.google.com/uc?export=download&id=1uTiIs3N7mjRuV0slrf_kGtWGPxGM5nz4" -O vhosts.conf
             sudo chown -R apache /var/www
             sudo chgrp -R apache /var/www
             cd /
             sudo chgrp -R apache /var/www
             sudo wget https://wordpress.org/latest.tar.gz
             sudo tar -xzf latest.tar.gz
             sudo cp -r wordpress/* /var/www/html/
             sudo mkdir /var/www/html/blog
             sudo cp -r wordpress/* /var/www/html/blog/
             sudo chgrp -R apache /var/www
             sudo cp -r wordpress/* /var/www/html/
             EOF 
              )*/
       user_data = base64encode(<<-EOF
                 #!/bin/bash
                 sudo apt update -y
                 sudo apt install apache2 -y
                 sudo apt install software-properties-common
                 sudo apt-add-repository --yes --update ppa:ansible/ansible
                 sudo apt install ansible -y 
                 cd /etc/ansible/
                 sudo wget "https://drive.google.com/uc?export=download&id=1ZND3YiwThkXOUgKNA9kHdrU54W7VGf8S" -O hosts
                

                 sudo apt install php -y libapache2-mod-php mariadb-server mariadb-client php-mysql
                 cd /etc/apache2/sites-available/
                 sudo wget "https://drive.google.com/uc?export=download&id=1uTiIs3N7mjRuV0slrf_kGtWGPxGM5nz4" -O wordpress.conf
                 sudo a2ensite wordpress.conf
                 sudo a2dissite 000-default.conf
                 sudo systemctl reload apache2
                 cd /
                 wget -O /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz
                 sudo tar -xzvf /tmp/wordpress.tar.gz -C /var/www
                 sudo chown -R www-data.www-data /var/www/wordpress 
                 cd / 
                 sudo wget "https://drive.google.com/uc?export=download&id=1jDA0clJrai_gZ8MxIRZK6NzrhHiXq9Va" -O update.yml  
                 ansible-playbook update.yml
                 EOF 
              
       )
}
     


#resource "aws_elb_attachment" "ASG" {
 # elb      = aws_elb.ASG.id
  #target_id        = aws_autoscaling_group.agents.arn
  #}
resource "aws_autoscaling_group" "agents" {
    
    name             = "agents"
    max_size         = "3"
    min_size         = "1"
    health_check_type         = "EC2"
    health_check_grace_period = 120
    
    desired_capacity  = 1
    force_delete      =  true
    vpc_zone_identifier  = [aws_subnet.public_subnet.id]
    #launch_configuration =aws_launch_configuration.word_conf.name
    launch_template {
    id      = aws_launch_template.agent.id
   
  }
    
    load_balancers = [
    aws_elb.ASG.id
  ]

    tag {
        key = "Name"
        value = "Agent Instance"
        propagate_at_launch = true
    }
}

resource "aws_autoscaling_policy" "agents-scale-up" {
    name = "agents-scale-up"
    scaling_adjustment = 1
    adjustment_type = "ChangeInCapacity"
    cooldown = 30
    autoscaling_group_name = aws_autoscaling_group.agents.name
}


resource "aws_autoscaling_policy" "agents-scale-down" {
    name = "agents-scale-down"
    scaling_adjustment = -1
   
    adjustment_type = "ChangeInCapacity"
    cooldown = 30
    autoscaling_group_name = aws_autoscaling_group.agents.name
}
resource "aws_cloudwatch_metric_alarm" "memory-high" { 
    alarm_name = "high-util-high-agents"

    comparison_operator = "GreaterThanThreshold"
    evaluation_periods = "1"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "60"
    statistic = "Average"
    threshold = "70"
    treat_missing_data ="ignore"
    alarm_description = "This metric monitors ec2 cpu utilization"
    alarm_actions = [
        aws_autoscaling_policy.agents-scale-up.arn
    ]
    dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.agents.name
    }
}

resource "aws_cloudwatch_metric_alarm" "memory-low" {
    alarm_name = "cpu-util-low-agents"
    comparison_operator = "LessThanThreshold"
    evaluation_periods = "1"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "60"
    statistic = "Average"
    threshold = "70"
    treat_missing_data ="ignore"
    alarm_description = "This metric monitors ec2 cpu utilization"
    alarm_actions = [
        aws_autoscaling_policy.agents-scale-down.arn
    ]
    dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.agents.name
    }
}
output "elb_dns_name" {
  value = aws_elb.ASG.dns_name
}

/*
resource "aws_db_subnet_group" "mysql" {
  name       = "main"
  subnet_ids = [aws_subnet.public_subnet.id,aws_subnet.private_subnet.id]

  tags = {
    Name = "My DB subnet group"
  }
}

resource "aws_security_group" "mysql" {
  name        = "MY_db"
  description = "Allow user"
  vpc_id      = aws_vpc.vpc.id

   
   ingress {
    description = "all Traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    }
   ingress {
    description = "mysql"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  } 
  tags={
    name="DB_SG"
  }
  
    
} 

  

resource "aws_db_instance" "mysql" {
    storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0.20"
  instance_class       = "db.t2.micro"
  name                 = "mydb"
  username             = "admin"
  publicly_accessible    = true
  password             = "snapdragon001"
  

  allocated_storage           = "20"
  
  db_subnet_group_name        = aws_db_subnet_group.mysql.id
  
  port                    = "3306"
 
  vpc_security_group_ids = [aws_security_group.mysql.id] 
  skip_final_snapshot  = "true"
}

resource "aws_db_snapshot" "test" {
  db_instance_identifier = aws_db_instance.mysql.id
  db_snapshot_identifier = "snapshot1234"
}
output "RD_endpoint" {
  value = aws_db_instance.mysql.endpoint
}
*/