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

  # Transfer the script
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

  # Execute installation script
  provisioner "remote-exec" {
    inline = [
      "echo 'Starting installation...'",
      "sudo chmod +x /tmp/scripts.sh",
      "sudo /tmp/scripts.sh",
      "echo 'Installation completed.'"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "15m"
    }
  }

  # Verify installations
  provisioner "remote-exec" {
    inline = [
      "echo '=== Checking Installation Status ==='",
      "echo 'SonarQube Status:'",
      "sudo systemctl status sonarqube --no-pager || true",
      "echo 'SonarQube Port:'",
      "sudo netstat -tulpn | grep 9000 || true",
      "echo 'Maven Status:'",
      "source /etc/profile.d/maven.sh && mvn -version || true",
      "echo 'Environment Variables:'",
      "echo 'MAVEN_HOME:' $MAVEN_HOME",
      "echo 'JAVA_HOME:' $JAVA_HOME",
      "echo 'Service Logs:'",
      "sudo journalctl -u sonarqube --no-pager -n 50 || true",
      "echo '=== Status Check Complete ==='"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
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