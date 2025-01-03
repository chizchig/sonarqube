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

  # Primary connection config for creation-time provisioners
  provisioner "file" {
    source      = "${path.module}/scripts.sh"
    destination = "/tmp/scripts.sh"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "10m"
    }
  }

  # Execute the bootstrap script
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/scripts.sh",
      "sudo /tmp/scripts.sh 2>&1 | tee /tmp/bootstrap.log || { echo 'Bootstrap failed. Check /tmp/bootstrap.log for details'; exit 1; }",
      "echo 'Verifying bootstrap completion...'",
      "test -f /var/log/bootstrap-complete || { echo 'Bootstrap completion marker not found'; exit 1; }",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rr.private_key_pem
      host        = self.public_ip
      timeout     = "10m"
    }
  }

  # Local cleanup instead of remote cleanup
  provisioner "local-exec" {
    when = destroy
    command = "echo 'Instance ${self.id} is being destroyed'"
  }

  # Optional: Wait for system status checks
  provisioner "local-exec" {
    command = <<-EOT
      aws ec2 wait instance-status-ok \
        --instance-ids ${self.id} \
        --region ${var.aws_region}
    EOT
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