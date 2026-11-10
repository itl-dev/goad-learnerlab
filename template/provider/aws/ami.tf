# [Learner Lab] AMI をリージョン非依存で自動検索する（ハードコードされた eu-west-3 の AMI ID を使わない）
data "aws_ami" "win2016" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2016-English-Full-Base-*"]
  }
}

data "aws_ami" "win2019" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
  }
}

data "aws_ami" "win2025" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-*"]
  }
}

data "aws_ami" "ubuntu_jammy" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

locals {
  windows_ami_by_sku = {
    "2016-Datacenter" = data.aws_ami.win2016.id
    "2019-Datacenter" = data.aws_ami.win2019.id
    "2025-Datacenter" = data.aws_ami.win2025.id
  }
}
