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
      "echo 'Starting debug script execution...'",
      "sudo chmod +x /tmp/scripts.sh",
      "echo 'Script permissions:'",
      "ls -l /tmp/scripts.sh",
      "echo 'Current working directory:'",
      "pwd",
      "echo 'Available memory:'",
      "free -h",
      "echo 'Disk space:'",
      "df -h",
      "echo 'Executing script with debug...'",
      "sudo bash -x /tmp/scripts.sh 2>&1 | tee /tmp/script_debug.log || {",
      "  echo '=== Script execution failed ==='",
      "  echo '=== Debug Log Content ==='",
      "  cat /tmp/script_debug.log",
      "  echo '=== System Messages ==='",
      "  sudo tail -n 50 /var/log/messages",
      "  echo '=== Disk Status ==='",
      "  df -h",
      "  echo '=== Mount Points ==='",
      "  mount",
      "  echo '=== Block Devices ==='",
      "  lsblk",
      "  exit 1",
      "}"
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