provider "google" {
  project = "your-project-id"
  region  = "your-region"
  // credentials는 IAM에서 서비스 계정 생성 후 키를 받아서 입력 ( 서비스 계정 생성 시 클러스터 생성 관련 권한이 있어야 함 )
  credentials = "your personal credentials starts with -> ${file("")}"
  zone = "your-region-zone"
}

// 서브넷 지정
data "google_compute_subnetwork" "subnet" {
  name = "db-sub"
  region = "us-central1"
}
# GCP 방화벽 규칙 생성
resource "google_compute_firewall" "mysql-from-gcp-aws" {
  name    = "mysql-connect"
  network = data.google_compute_subnetwork.subnet.network

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }

  source_ranges = [ "10.0.0.0/8" ]
  target_tags = ["mysql"]
}

resource "google_compute_firewall" "mysql-vm-ssh" {
  name = "mysql-ssh-connection"
  network = data.google_compute_subnetwork.subnet.network

  allow {
    protocol = "tcp"
    ports = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags = ["mysql"]
}

resource "google_compute_firewall" "mysql-vm-connect" {
  name = "mysql-connect-vm"
  network = data.google_compute_subnetwork.subnet.network

  allow {
    protocol = "tcp"
    ports = [ "3306" ]
  }
  source_tags = [ "mysql" ]
  target_tags = [ "mysql" ]
}

resource "google_compute_instance" "mysql-master" {
  name         = "mysql-master"
  machine_type = "n1-standard-1"
  zone         = "us-central1-a"
  tags = [ "mysql" ]
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network = data.google_compute_subnetwork.subnet.network
    subnetwork = data.google_compute_subnetwork.subnet.name
    // Ip를 스태틱으로 준 이유는 mysql replication 활성화를 한번에 하기 위함
    network_ip = "192.168.100.11" // <- 본인의 사설 ip 주소로 변경
    access_config {
    }
  }

  metadata_startup_script = <<-SCRIPT
    #!/bin/bash

    # Install MySQL
    sudo apt-get update
    sudo apt-get install -y mysql-server

    # Update MySQL config file
    sudo sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i 's/^#[[:space:]]server-id.*/server-id=1/' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i 's/^#[[:space:]]log_bin.*/log_bin=mysql-bin/' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i 's/^#[[:space:]]binlog_do_db.*/binlog_do_db=/' /etc/mysql/mysql.conf.d/mysqld.cnf
    # binlog_do_db 를 비워두면 ignore_db 를 제외한 모든 데이터베이스가 복제된다. 보안상 위험하므로 지정해주는 게 좋다. 테스트여서 빈칸
    sudo sed -i 's/^#[[:space:]]binlog_ignore_db.*/binlog_ignore_db=mysql/' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i '/binlog_ignore_db/ a\binlog_ignore_db=information_schema' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i '/binlog_ignore_db=i/ a\binlog_ignore_db=preformance_schema' /etc/mysql/mysql.conf.d/mysqld.cnf


    # Restart MySQL service
    sudo systemctl restart mysql

    # Set up replication user and privileges
    sudo mysql -e "CREATE USER 'repliuser'@'192.168.100.12' IDENTIFIED BY 'repl1234';"
    sudo mysql -e "CREATE USER 'repliuser'@'192.168.100.13' IDENTIFIED BY 'repl1234';"
    sudo mysql -e "CREATE USER 'repliuser'@'10.0.10.' IDENTIFIED BY 'repl1234';"
    sudo mysql -e "GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'repliuser'@'192.168.100.12';"
    sudo mysql -e "GRANT REPLICATION SLAVE ON *.* TO 'repliuser'@'192.168.100.13';"
    sudo mysql -e "ALTER USER 'repliuser'@'192.168.100.12' IDENTIFIED WITH mysql_native_password BY 'repl1234';"
    sudo mysql -e "ALTER USER 'repliuser'@'192.168.100.13' IDENTIFIED WITH mysql_native_password BY 'repl1234';"
    

    # Set up replication
    sudo mysql -e "CHANGE MASTER TO MASTER_HOST='192.168.100.12', MASTER_USER='repliuser1', MASTER_PASSWORD='repl1234', MASTER_LOG_FILE='mysql-bin.000001', MASTER_LOG_POS=0;"
    sudo mysql -e "START SLAVE;"

  SCRIPT
}

# GCP 인스턴스 2 생성
resource "google_compute_instance" "mysql-slave" {
  name         = "mysql-slave"
  machine_type = "n1-standard-1"
  zone         = "your-region-zone"
  tags = [ "mysql" ]
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network = data.google_compute_subnetwork.subnet.network
    subnetwork = data.google_compute_subnetwork.subnet.name
    network_ip = "192.168.100.12"
    access_config {
      
    }
  }

  metadata_startup_script = <<-SCRIPT
    #!/bin/bash

    # Install MySQL
    sudo apt-get update
    sudo apt-get install -y mysql-server

    # Update MySQL config file
    sudo sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i 's/^#[[:space:]]server-id.*/server-id=2/' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i 's/^#[[:space:]]log_bin.*/log_bin=mysql-bin/' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i 's/^#[[:space:]]binlog_do_db.*/binlog_do_db=/' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i 's/^#[[:space:]]binlog_ignore_db.*/binlog_ignore_db=mysql/' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i '/binlog_ignore_db/ a\binlog_ignore_db=information_schema' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i '/binlog_ignore_db=i/ a\binlog_ignore_db=preformance_schema' /etc/mysql/mysql.conf.d/mysqld.cnf

    # Restart MySQL service
    sudo systemctl restart mysql

    # Set up replication user and privileges
    sudo mysql -e "CREATE USER 'repliuser1'@'192.168.100.11' IDENTIFIED BY 'repl1234';"
    sudo mysql -e "GRANT REPLICATION SLAVE ON *.* TO 'repliuser1'@'192.168.100.11';"
    sudo mysql -e "ALTER USER 'repliuser1'@'192.168.100.11' IDENTIFIED WITH mysql_native_password BY 'repl1234';"

    # Set up replication
    sudo mysql -e "CHANGE MASTER TO MASTER_HOST='192.168.100.11', MASTER_USER='repliuser', MASTER_PASSWORD='repl1234', MASTER_LOG_FILE='mysql-bin.000001', MASTER_LOG_POS=0;"
    sudo mysql -e "START SLAVE;"


  SCRIPT
}

resource "google_compute_instance" "mysql-slave-1-1" {
  name         = "mysql-second-slave"
  machine_type = "n1-standard-1"
  zone         = "your-region-zone"
  tags         = ["mysql"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network = data.google_compute_subnetwork.subnet.network
    subnetwork = data.google_compute_subnetwork.subnet.name
    network_ip = "192.168.100.13"

    access_config {
    }
  }

  metadata_startup_script = <<-SCRIPT
    #!/bin/bash

    # Install MySQL
    sudo apt-get update
    sudo apt-get install -y mysql-server

    # Update MySQL config file
    sudo sed -i 's/^#[[:space:]]server-id.*/server-id=3/' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i 's/^#[[:space:]]log_bin.*/log_bin=mysql-bin/' /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo sed -i '/log_bin/ a\read_only=1' /etc/mysql/mysql.conf.d/mysqld.cnf


    # Restart MySQL service
    sudo systemctl restart mysql

    # Set up replication user and privileges
    sudo mysql -e "CREATE USER 'repliuser'@'192.168.100.11' IDENTIFIED BY 'repl1234';"
    sudo mysql -e "GRANT REPLICATION SLAVE ON *.* TO 'repliuser'@'192.168.100.11';"
    sudo mysql -e "ALTER USER 'repliuser'@'192.168.100.11' IDENTIFIED WITH mysql_native_password BY 'repl1234';"

    # Set up replication
    sudo mysql -e "CHANGE MASTER TO MASTER_HOST='192.168.100.11', MASTER_USER='repliuser', MASTER_PASSWORD='repl1234', MASTER_LOG_FILE='mysql-bin.000001', MASTER_LOG_POS=0;"
    sudo mysql -e "START SLAVE;"

  SCRIPT
}
