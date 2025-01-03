instance_type               = "t2.medium"
ami_id                      = "ami-0a5c3558529277641"
aws_region                  = "us-east-1"

internal_subnet_cidr_blocks = [ "10.0.3.0/24", "10.0.4.0/24" ]
external_subnet_cidr_blocks = [ "10.0.1.0/24", "10.0.2.0/24" ]
vpc_cidr_block              = "10.0.0.0/16"
security_group_name         = "sonarqube-sg"

ingress_rules = [
  {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  },
  {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  
  }
]

egress_rules = [
  {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
]

tags = {
  "Environment" = "dev"
}