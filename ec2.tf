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

  # Initial setup and debug info
  provisioner "remote-exec" {
    inline = [
      "echo 'Testing initial connection...'",
      "echo 'Current user: '$(whoami)",
      "echo 'Home directory: '$(pwd)",
      "echo 'System info: '$(uname -a)",
      "echo 'Available disk space: '",
      "df -h",
      "echo 'Memory info: '",
      "free -h",
      "echo 'Initial setup complete'"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }
  }

  # Transfer the script with debug mode
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

  # Execute script with extensive debugging
  provisioner "remote-exec" {
    inline = [
      "echo 'Starting SonarQube installation...'",
      "sudo chmod +x /tmp/scripts.sh",
      "echo 'Made script executable'",
      "if sudo /tmp/scripts.sh; then",
      "  echo 'SonarQube installation completed successfully'",
      "  sudo systemctl status sonarqube",
      "else",
      "  echo 'SonarQube installation failed'",
      "  echo 'Checking logs...'",
      "  sudo journalctl -u sonarqube --no-pager -n 100",
      "  sudo cat /tmp/script_debug.log",
      "  exit 1",
      "fi"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "15m"
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