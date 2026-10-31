provider "aws"{
  region = "us-east-1"
  }

terraform {
  backend "s3" {
   region = "us-east-1"
   bucket = "kuldeep5-9-00"
   key    =  "terra.tf"
}
}
/* terraform {
  backend "local" {
    path = "/root/dir1/terraform.tfstate1"
  }
}
*/
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/24"
  tags = {
    Name = "my-vpc"
  }
}
resource "aws_subnet" "pub_sub1" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.0.0/25"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"
  tags = {
    Name = "my-sub1"
  }
}
resource "aws_subnet" "pub_sub2" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.0.128/25"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "my-sub2"
  }
}

resource "aws_internet_gateway" "Igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "IGW"
  }
}
resource "aws_default_route_table" "main-rt" {
  default_route_table_id = aws_vpc.my_vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.Igw.id
  }
}
resource "aws_db_subnet_group" "database" {
  name       = "my-db-sub-grp"
  subnet_ids = [aws_subnet.pub_sub1.id, aws_subnet.pub_sub2.id]

  tags = {
    Name = "database"
  }
}

resource "aws_security_group" "my_sg" {
    name        = "my-sg"
    description = "ssh & http"
    vpc_id      = aws_vpc.my_vpc.id
  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
}
  ingress {
    from_port        = 8080
    to_port          = 8080
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
}
  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
  }
   egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
}
}

variable "image_id"{
    default = "ami-0b4322fc894fcd794"
}
 
 data "template_file" "my_tpl" {
  template = file("./context.tpl")

  vars = {
     endpoint = aws_db_instance.rds.address
  }
}
  resource "aws_instance" "my_instance1" {
   ami = var.image_id
   instance_type = "t2.micro"
   vpc_security_group_ids = [aws_security_group.my_sg.id]
   key_name = "my-key"
   #depends_on = [aws_db_instance.rds]
   connection {
     type = "ssh"
     private_key = file("./my-key.pem")
     host = self.public_ip
     user = "ec2-user"
   }
   provisioner "file" {
     source = "./index.html"
     destination = "/home/ec2-user"
   }  
   provisioner "remote-exec"{
    inline =[ "sudo cp /home/ec2-user/index.html  /usr/share/nginx/html/index.html"
    ]
   }
  }
 resource "aws_instance" "my_instance" {
   ami = var.image_id
   instance_type = "t2.micro"
   vpc_security_group_ids = [aws_security_group.my_sg.id]
   key_name = "my-key"
   depends_on = [aws_db_instance.rds]
   user_data = <<-EOF
              #!/bin/bash
              echo '${data.template_file.my_tpl.rendered}' > /opt/apache-tomcat-9.0.100/conf/context.xml
              EOF
   connection {
    type        = "ssh"
    user        = "ec2-user"  # For Amazon Linux; use "ubuntu" for Ubuntu
    private_key = file("./my-key.pem")  # Replace with your private key path
    host        = self.public_ip
  }

   provisioner "file" {
    source      = "./student.war"  # File from your local machine
    destination = "/opt/apache-tomcat-9.0.100/webapps/student.war"  # Path on EC2 instance
  }
  provisioner "file" {
    source      = "./mysql-connector.jar"  # File from your local machine
    destination = "/opt/apache-tomcat-9.0.100/lib/mysql-connector.jar"  # Path on EC2 instance
  }
  provisioner "file" {
  source      = "./mydb.sql"
  destination = "/home/ec2-user/mydb.sql"
  }

  provisioner "remote-exec" {
      inline = [
        "sudo /opt/apache-tomcat-9.0.100/bin/catalina.sh start"
      ]
   }

   provisioner "remote-exec" {
    inline = [
       "sudo mysql -h ${aws_db_instance.rds.address} -u admin -p12345678 -e 'CREATE DATABASE IF NOT EXISTS mydb;'",
      "sudo mysql -h  ${aws_db_instance.rds.address} -u admin -p12345678 mydb < /home/ec2-user/mydb.sql"
            ]
   }
}

  resource "aws_db_instance" "rds" {
  allocated_storage    = 20
  db_name              = "mydb"
  db_subnet_group_name = aws_db_subnet_group.database.name
  vpc_security_group_ids= [aws_security_group.my_sg.id]
  publicly_accessible    = false
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  username             = "admin"
  password             = "12345678"
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
}