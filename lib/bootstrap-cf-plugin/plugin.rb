require "bootstrap-cf-plugin"

module BootstrapCfPlugin
  class Plugin < CF::CLI
    STATIC_TOKENS = [
      {provider: 'sendgrid-dev', label: 'smtp', token: 'ad_smtp_sendgriddev_token'},
      {provider: 'mongolab-dev', label: 'mongodb', token: 'ad_mongodb_mongolabdev_token'},
      {provider: 'redistogo-dev', label: 'redis', token: 'ad_redis_redistogodev_token'}
    ]

    def precondition
      # skip all default preconditions
    end

    def lookup_infrastructure_class(infrastructure)
      infrastructure_module = Kernel.const_get("BootstrapCfPlugin").const_get("Infrastructure")
      infrastructure_module.const_get(infrastructure) if infrastructure_module.const_defined?(infrastructure)
    end

    def tokens_from_jobs(jobs)
      jobs.each_with_object([]) do |job, gateways|
        if job['properties']
          job['properties'].each do |k,v|
            if v.is_a?(Hash) && v['token']
              gateways << {label: k.gsub("_gateway", "").gsub("rabbit", "rabbitmq"), token: v['token'], provider: 'core'}
            end
          end
        end
      end
    end

    desc "Bootstrap a CF deployment"
    group :admin
    input :infrastructure, :argument => :required, :desc => "The infrastructure to bootstrap and deploy"
    input :template, :argument => :optional, :desc => "The template file for the CF deployment"
    def bootstrap
      infrastructure = input[:infrastructure].to_s.capitalize
      infrastructure_class = lookup_infrastructure_class(infrastructure)
      raise "Unsupported infrastructure #{input[:infrastructure]}" unless infrastructure_class
      DirectorCheck.check
      infrastructure_class.bootstrap(input[:template])

      cf_aws_manifest = load_yaml_file("cf-aws.yml")
      cf_properties = cf_aws_manifest.fetch('properties')
      uaa_users = cf_properties.fetch('uaa').fetch('scim').fetch('users')

      uaa_user = uaa_users.first.split("|")

      invoke :logout
      invoke :target, :url => cf_properties.fetch('cc').fetch('srv_api_uri')

      invoke :login, :username => uaa_user[0], :password => uaa_user[1]

      invoke :create_org, :name => 'bootstrap-org'

      org = client.organization_by_name("bootstrap-org")
      invoke :create_space, :organization => org, :name => "bootstrap-space"

      space = client.space_by_name("bootstrap-space")
      invoke :target, :url => cf_properties.fetch('cc').fetch('srv_api_uri'), :organization => org, :space => space

      # invoke a bunch of create-service-token commands
      (tokens_from_jobs(cf_aws_manifest.fetch('jobs', [])) + STATIC_TOKENS).each do |gateway_info|
        invoke :create_service_auth_token, gateway_info
      end
    end

    desc "Generate a manifest stub"
    group :admin
    input :infrastructure, :argument => :required, :desc => "The infrastructure for which to generate a stub"
    def generate_stub
      infrastructure = input[:infrastructure].to_s.capitalize
      infrastructure_class = lookup_infrastructure_class(infrastructure)
      raise "Unsupported infrastructure #{input[:infrastructure]}" unless infrastructure_class
      DirectorCheck.check
      infrastructure_class.generate_stub
    end
  end
end
