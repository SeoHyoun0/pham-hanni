provider "google" {
  project = "your-project-id"
  region  = "your-region"
  // credentials는 IAM에서 서비스 계정 생성 후 키를 받아서 입력 ( 서비스 계정 생성 시 클러스터 생성 관련 권한이 있어야 함 )
  credentials = "your personal credentials starts with -> ${file("")}"
  zone = "your-region-zone"
}
// 서브넷이 따로 없고 default 만 있으면 비워도됨
data "google_compute_subnetwork" "subnet" {
    name = "gke-webwas-cluster"
    region = "your-region"
}


resource "google_container_cluster" "my-cluster" {
  name = "my-cluster"
  location = "your-region-zone"

  // 클러스터 구성 시 기본 노드 개수 지정
  initial_node_count = 2
  
  // 서브넷 따로 없이 default 만 있으면 밑에 두 라인이 없어도 알아서 default에 만들어짐
  network = data.google_compute_subnetwork.subnet.network
  subnetwork = data.google_compute_subnetwork.subnet.name

  master_auth {
    client_certificate_config {
        issue_client_certificate = false
    }
  }
  // 노드 머신 구성
  node_config {
    machine_type = "e2-standard-8"

    metadata = {
        disable_legacy_endpoints = "true"
    }
    oauth_scopes = [
    "https://www.googleapis.com/auth/compute",
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring"
    ]

    tags = ["my-cluster-node"]
  }
  
  lifecycle {
    ignore_changes = [
        node_config[0].tags
    ]
  }
}

// null 리소스와 depends_on 을 사용하면 클러스터 구성 후 클러스터 로그인까지 가능하고, 이후 터미널에서 번거롭게 타이핑해야할 명령어를 줄여줄 수 있음
resource "null_resource" "login_to_cluster" {
  depends_on = [
    google_container_cluster.my-cluster
  ]
  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${google_container_cluster.my-cluster.name} --region=${google_container_cluster.my-cluster.location}"
  }
}