
# Test Project

This is test project where we're using Terraform, Ansible, K8s (k3s) and Argocd to create envirometn to run our cron job which generates random number and stores it as a file in S3 bucket

Structure

# Structure


```shell
├── ansible # Ansible used to create k3s cluster
│   ├── ansible.cfg
│   ├── k3s.yml
├── app     # Our python app
│   ├── Dockerfile
│   ├── VERSION.TXT
│   ├── main.py
│   └── requirements.txt
├── kube # core configuration
│   ├── app  # Our python app
│   │   ├── cronjob.yaml
│   │   └── kustomization.yaml
│   ├── argocd # Utore aplication here 
│   │   └── application.yaml
│   └── umbrella # Umbrella chart to install Argo
│       ├── Chart.yaml
│       └── values.yaml
└── terraform
    ├── backend  # Remote backend initialization
    │   ├── main.tf 
    │   ├── outputs.tf
    │   └── variables.tf
    └── infra   # Create our ec2 and s3 bucket
        ├── main.tf
        ├── outputs.tf
        └── variables.tf

```

# How to start

## Create your AWS account and initialize backend
You need to create an AWS free tier account, create an IAM user for terraform, create an EC2 key-pair.

Store your terraforms IAM user's ID and Key and using aws cli configure.

Then you can initialize a backend

```shell
aws configure
cd terraform/backend
terraform init
terraform apply
```

Outputs will provide you an S3 bucket and DynamoDB table to store your lock and state - add them to your main.tf file in terraform/infra directory 

```shell
backend "s3" {
    bucket         = "tf-backend-tfstate-0f719b6b"
    key            = "infra/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tf-backend-tfstate-lock"
    encrypt        = true
  }
}
```

## Create your EC2 and S3

Now after you have initilazied your backend you can simply go to your /terraform/infra/ directory and run your terraform to create your infrastructure

```shell
cd terraform/infra
terraform init
terraform plan
terraform apply
```

But don't forget to create your terraform.tfvars file first!!!

```shell
aws_region = "eu-central-1"
project    = "s3-random-writer"
my_ip_cidr = "X.X.X.X/32"
key_name   = "terraform-key"
```

After apply you will have on your AWS:
 - EC2 instance
 - S3 bucket where generated numbers will store

 Configuration for S3:
 - aws_s3_bucket - creates bucket (resource random_id will give it random id and suffix)
 - aws_s3_bucket_public_access_block - bucket is closed for inbound
 - aws_s3_bucket_server_side_encryption_configuration - AES256 cipher
 - aws_s3_bucket_versioning - Versioning
 - aws_s3_bucket_lifecycle_configuration - lifecycle policy

 VPC:
 - data "aws_vpc" "default" { default = true }
   data "aws_subnets" "default" { filter vpc-id = default-vpc }
   locals { subnet_id = tolist(...)[0] } creates default vpc (quickstart)

 Security Group:
 - aws_security_group - allow 22/tcp and 6443/tcp from my_ip_cidr

 IAM:
 - aws_iam_policy_document - allows ec2.amazonaws.com using this role 
 - aws_iam_role - creates ec2_role
 - aws_iam_policy_document - gives access form EC2 to our S3 bucket
 - aws_iam_instance_profile - gives instance a profile to use role

 EC2:
 - aws_ami - finds latest ubuntu 22.04 image
 - aws_instance - creates your instance 

 ## Run ansible playbook to initialize your cluster

 After your infra is ready you can go to ansible directory and run your playbook to initialize k3s cluster

 But firstly using your outputs from terraform you need to create inventory.ini file :

 ```shell
[k3s]
node ansible_host=your_ec2_ip ansible_user=ubuntu ansible_ssh_private_key_file=./your.ssh-key.pem
```
 And create ansible.cfg file: 

 ```shell
[defaults]
inventory = inventory.ini
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
```

Then you can run an ansible playbook:
```shell
pip install ansible
ansible-playbook k3s.yml 
```
After running ansible playbook you will recieve kubeconfig file.
Use it!

## Instal argocd

Now you have your kubeconfig you can install argo:

```shell
helm dependency update kube/umbrella
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install platform kube/umbrella \
  -n argocd \
  -f kube/umbrella/values.yaml \
  --wait
kubectl -n argocd get pods

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Now you can login - http://localhost:8080
Connect you repo!

## Create application

Now you can create our application:

```shell
kubectl apply -f kube/argocd/application.yaml
```

Now we can see our app in UI 

## k8s configuration

Our app is simple - cronjob configuration + kustomization for cd

The only thing you need to do its add your bucket to manifest:
```shell
- name: S3_BUCKET
    value: your_bucket_for_numbers
```

## CI/CD 

CI configured using Github Actions 
It builds image - pushing it to registry - changing tag in kustomization

Triggers only on main branch and if changes are in paths:
      - app/**
      - kube/app/**
To update tag you need to update your app/VERSION.TXT file


