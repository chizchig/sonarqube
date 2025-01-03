resource "tls_private_key" "rr" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "key" {
  depends_on = [tls_private_key.rr]
  content    = tls_private_key.rr.private_key_pem
  filename   = "${path.module}/private_key.pem"  # Save the private key securely
}

resource "aws_key_pair" "rr-tf" {
  key_name   = "key-tf"
  public_key = tls_private_key.rr.public_key_openssh  # Use the generated public key
}
