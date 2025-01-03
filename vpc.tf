# Data sources
data "aws_availability_zones" "available" {}

# Function to generate a random string
resource "random_string" "vpc_name" {
  length  = 8
  special = false
}

# Resources
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    name = "vpc-${random_string.vpc_name.result}"
  }
}

resource "aws_subnet" "external_subnets" {
  for_each = { for idx, block in var.external_subnet_cidr_blocks : idx => { "cidr_block" = block, "availability_zone" = data.aws_availability_zones.available.names[idx] } }

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value["cidr_block"]
  availability_zone       = each.value["availability_zone"]
  map_public_ip_on_launch = true

  tags = {
    Name = "ExternalSubnet-${each.key}-${random_string.vpc_name.result}"
  }
}

resource "aws_subnet" "internal_subnets" {
  for_each = {
    for idx, block in var.internal_subnet_cidr_blocks : "database_instance${idx}" => { "cidr_block" = block, "availability_zone" = data.aws_availability_zones.available.names[idx] }
  }

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value["cidr_block"]
  availability_zone       = each.value["availability_zone"]
  map_public_ip_on_launch = false

  tags = {
    Name = "InternalSubnet-${each.key}-${random_string.vpc_name.result}"
  }
}



resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "InternetGateway-${random_string.vpc_name.result}"
  }
}

resource "aws_route_table" "external_route_tables" {
  for_each = aws_subnet.external_subnets

  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "external-route-table-${each.key}"
  }
}

resource "aws_route_table_association" "external_associations" {
  for_each = aws_subnet.external_subnets

  subnet_id      = each.value.id
  route_table_id = aws_route_table.external_route_tables[each.key].id
}

resource "aws_route_table" "internal_route_tables" {
  for_each = aws_subnet.internal_subnets

  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "internal-route-table-${each.key}"
  }
}

resource "aws_route_table_association" "internal_associations" {
  for_each = aws_subnet.internal_subnets

  subnet_id      = each.value.id
  route_table_id = aws_route_table.internal_route_tables[each.key].id
}