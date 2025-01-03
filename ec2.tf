resource "aws_instance" "bootstrap_instance" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.rr-tf.key_name
  subnet_id                   = aws_subnet.external_subnets[0].id
  vpc_security_group_ids      = [aws_security_group.aurora_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = "100"
    volume_type          = "gp2"
    encrypted            = true
    delete_on_termination = true
  }

  ebs_block_device {
    device_name           = "/dev/xvda"
    volume_size           = "1000"
    volume_type          = "gp2"
    encrypted            = true
    delete_on_termination = true
  }

  # Add a delay to ensure instance is ready
  provisioner "local-exec" {
    command = "sleep 30"
  }

  # Initial connection test
  provisioner "remote-exec" {
    inline = ["echo 'Connected successfully'"]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }
  }

  # File transfer with error checking
  provisioner "file" {
    source      = "${path.module}/scripts.sh"
    destination = "/tmp/scripts.sh"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }
  }

  # Execute bootstrap with better error handling
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/scripts.sh",
      "echo 'Starting bootstrap script execution...'",
      "if sudo /tmp/scripts.sh; then",
      "  echo 'Bootstrap completed successfully'",
      "else",
      "  echo 'Bootstrap failed with exit code $?'",
      "  sudo cat /tmp/bootstrap.log",
      "  exit 1",
      "fi",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "10m"
    }
  }

  tags = {
    Name        = "Bootstrap_Instance"
    Environment = var.environment
    Provisioner = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}