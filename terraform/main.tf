# TODO: Adicionar tags comuns a todos os recursos para governança e rastreamento de custos

module "networking" {
  source = "./modules/networking"

  project_name     = var.project_name
  vpc_cidr         = var.vpc_cidr
  ssh_allowed_cidr = var.ssh_allowed_cidr
}

module "database" {
  source = "./modules/database"

  project_name          = var.project_name
  db_username           = var.db_username
  db_password           = var.db_password
  db_name               = var.db_name
  rds_instance_class    = var.rds_instance_class
  private_subnet_ids    = module.networking.private_subnet_ids
  rds_security_group_id = module.networking.rds_security_group_id
}

module "compute" {
  source = "./modules/compute"

  project_name          = var.project_name
  ec2_instance_type     = var.ec2_instance_type
  ec2_public_key        = var.ec2_public_key
  public_subnet_id      = module.networking.public_subnet_id
  ec2_security_group_id = module.networking.ec2_security_group_id

  # Database connection info for user_data
  rds_endpoint = module.database.rds_endpoint
  db_name      = var.db_name
  db_username  = var.db_username
  db_password  = var.db_password

  # Moodle configuration
  repo_url              = var.repo_url
  moodle_admin_user     = var.moodle_admin_user
  moodle_admin_password = var.moodle_admin_password
  moodle_site_name      = var.moodle_site_name
}
