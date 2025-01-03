resource "tls_private_key" "rr" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "rr-tf" {
  key_name_prefix = "key-tf-"  # Using prefix instead of fixed name
  public_key      = tls_private_key.rr.public_key_openssh

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      key_name_prefix
    ]
  }

  tags = {
    Name        = "terraform-generated-key"
    Environment = var.environment
  }
}
