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

  # Wait for instance to be ready
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for instance..."
      aws ec2 wait instance-status-ok \
        --instance-ids ${self.id} \
        --region ${var.aws_region}
      echo "Instance is ready!"
    EOT
  }

  # Test SSH connectivity first
  provisioner "remote-exec" {
    inline = [
      "echo 'Testing SSH connection...'",
      "whoami",
      "pwd",
      "echo 'SSH connection successful'",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
      agent       = false
    }
  }

  # Transfer the script file
  provisioner "file" {
    source      = "${path.module}/scripts.sh"
    destination = "/tmp/scripts.sh"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
      agent       = false
    }
  }

  # Execute script with debugging
  provisioner "remote-exec" {
    inline = [
      "echo 'Setting up script...'",
      "sudo chmod +x /tmp/scripts.sh",
      "echo 'Starting script execution...'",
      "sudo bash -x /tmp/scripts.sh || {",
      "  echo 'Script failed. Checking logs...'",
      "  echo '=== Last 50 lines of system log ==='",
      "  sudo tail -n 50 /var/log/messages",
      "  echo '=== Script output ==='",
      "  cat /tmp/bootstrap.log",
      "  exit 1",
      "}"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "15m"
      agent       = false
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