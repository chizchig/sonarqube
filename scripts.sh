#!/bin/bash

# Exit on error
set -e

echo "Starting SonarQube installation..."

# Backup and configure system settings
sudo cp /etc/sysctl.conf /root/sysctl.conf_backup
sudo tee /etc/sysctl.conf << EOT
vm.max_map_count=524288
fs.file-max=131072
EOT

# Apply sysctl settings
sudo sysctl --system

# Configure security limits
sudo cp /etc/security/limits.conf /root/sec_limit.conf_backup
sudo tee /etc/security/limits.conf << EOT
sonarqube   -   nofile   131072
sonarqube   -   nproc    8192
* soft nofile 131072
* hard nofile 131072
* soft nproc 8192
* hard nproc 8192
EOT

# Install Java 17
echo "Installing Java 17..."
sudo yum remove java* -y || true
sudo yum install -y java-17-amazon-corretto
java -version

# Install PostgreSQL 14
echo "Installing PostgreSQL..."
sudo yum install -y postgresql14 postgresql14-server
sudo /usr/bin/postgresql-14-setup initdb
sudo systemctl enable postgresql-14
sudo systemctl start postgresql-14

# Configure PostgreSQL
echo "Configuring PostgreSQL..."
sudo -u postgres psql << EOF
CREATE USER sonar WITH ENCRYPTED PASSWORD 'admin123';
CREATE DATABASE sonarqube OWNER sonar;
GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonar;
\q
EOF

# Configure PostgreSQL authentication
sudo sed -i 's/peer/trust/g' /var/lib/pgsql/14/data/pg_hba.conf
sudo sed -i 's/ident/md5/g' /var/lib/pgsql/14/data/pg_hba.conf
sudo systemctl restart postgresql-14

# Download and install SonarQube
echo "Installing SonarQube..."
sudo mkdir -p /sonarqube/
cd /sonarqube/
sudo curl -O https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-10.3.0.82913.zip
sudo yum install unzip -y
sudo unzip -o sonarqube-10.3.0.82913.zip -d /opt/
sudo mv /opt/sonarqube-10.3.0.82913/ /opt/sonarqube

# Create sonar user and set permissions
sudo groupadd sonar || true
sudo useradd -c "SonarQube - User" -d /opt/sonarqube/ -g sonar sonar || true
sudo chown sonar:sonar /opt/sonarqube/ -R

# Configure SonarQube
sudo cp /opt/sonarqube/conf/sonar.properties /root/sonar.properties_backup
sudo tee /opt/sonarqube/conf/sonar.properties << EOT
sonar.jdbc.username=sonar
sonar.jdbc.password=admin123
sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube
sonar.web.host=0.0.0.0
sonar.web.port=9000
sonar.web.javaAdditionalOpts=-server
sonar.search.javaOpts=-Xmx2048m -Xms2048m -XX:+HeapDumpOnOutOfMemoryError
sonar.ce.javaOpts=-Xmx2048m -Xms1024m -XX:+HeapDumpOnOutOfMemoryError
sonar.web.javaOpts=-Xmx2048m -Xms1024m -XX:+HeapDumpOnOutOfMemoryError
sonar.log.level=INFO
sonar.path.logs=logs
sonar.path.data=/opt/sonarqube/data
sonar.path.temp=/opt/sonarqube/temp
EOT

# Create systemd service
sudo tee /etc/systemd/system/sonarqube.service << EOT
[Unit]
Description=SonarQube service
After=syslog.target network.target postgresql-14.service

[Service]
Type=simple
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh console
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=sonar
Group=sonar
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sonarqube/logs/stdout.log
StandardError=append:/opt/sonarqube/logs/stderr.log
LimitNOFILE=131072
LimitNPROC=8192
TimeoutStartSec=180
Environment=JAVA_HOME=/usr/lib/jvm/java-17
Environment=PATH=/usr/lib/jvm/java-17/bin:${PATH}

[Install]
WantedBy=multi-user.target
EOT

# Install and configure Nginx
echo "Installing and configuring Nginx..."
sudo yum install nginx -y
sudo tee /etc/nginx/conf.d/sonarqube.conf << EOT
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
}
EOT

# Start services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable sonarqube
sudo systemctl start sonarqube
sudo systemctl enable nginx
sudo systemctl start nginx

# Create convenience script for logs
sudo tee /usr/local/bin/sonar-logs << EOF
#!/bin/bash
echo "=== SonarQube Logs ==="
sudo tail -f /opt/sonarqube/logs/sonar.log /opt/sonarqube/logs/web.log /opt/sonarqube/logs/ce.log /opt/sonarqube/logs/es.log
EOF
sudo chmod +x /usr/local/bin/sonar-logs

echo "Installation complete! Please wait a few minutes for SonarQube to initialize."
echo "You can access SonarQube at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Default credentials: admin/admin"
echo "To view logs, run: sonar-logs"

# No immediate reboot - let user decide when to reboot
echo "NOTE: A system reboot is recommended. Run 'sudo reboot' when ready."