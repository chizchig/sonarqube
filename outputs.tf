# Output the instance details
output "bootstrap_instance_ip" {
  value = aws_instance.bootstrap_instance.public_ip
}

output "bootstrap_instance_id" {
  value = aws_instance.bootstrap_instance.id
}

output "bootstrap_completion_status" {
  value = "Check /tmp/bootstrap.log on the instance for detailed status"
}