require "bootstrap-cf-plugin"

module BootstrapCfPlugin
  class Plugin < CF::CLI
    def precondition
      # skip all default preconditions
    end

    def lookup_infrastructure_class(infrastructure)
      infrastructure_class = infrastructure.to_s.capitalize
      infrastructure_module = ::BootstrapCfPlugin::Infrastructure
      if infrastructure_module.const_defined?(infrastructure_class)
        infrastructure_module.const_get(infrastructure_class)
      else
        raise "Unsupported infrastructure #{infrastructure}"
      end
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
      infrastructure = input[:infrastructure]
      infrastructure_class = lookup_infrastructure_class(infrastructure)
      DirectorCheck.check
      infrastructure_class.bootstrap(input[:template])

      cf_manifest = load_yaml_file("cf-#{infrastructure}.yml")
      cf_services_manifest = load_yaml_file("cf-services-#{infrastructure}.yml")
      cf_properties = cf_manifest.fetch('properties')
      uaa_users = cf_properties.fetch('uaa').fetch('scim').fetch('users')

      uaa_user = uaa_users.first.split("|")

      invoke :logout
      invoke :target, :url => cf_properties.fetch('cc').fetch('srv_api_uri')

      invoke :login, :username => uaa_user[0], :password => uaa_user[1]

      org = find_or_create_org("bootstrap-org")

      space = find_or_create_space(org, "bootstrap-space")
      invoke :target, :url => cf_properties.fetch('cc').fetch('srv_api_uri'), :organization => org, :space => space

      # invoke a bunch of create-service-token commands
      (tokens_from_jobs(cf_services_manifest.fetch('jobs', []))).each do |gateway_info|
        begin
          invoke :create_service_auth_token, gateway_info
        rescue CFoundry::ServiceAuthTokenLabelTaken => e
          puts "  Don't worry, service token already installed, continuing"
        end
      end
      puts "All done with bootstrap!"
    end


    desc "Generate a manifest stub"
    group :admin
    input :infrastructure, :argument => :required, :desc => "The infrastructure for which to generate a stub"
    def generate_stub
      infrastructure = input[:infrastructure]
      infrastructure_class = lookup_infrastructure_class(infrastructure)
      DirectorCheck.check
      SharedSecretsFile.find_or_create("cf-shared-secrets.yml")
      infrastructure_class.generate_stub("cf-#{infrastructure}-stub.yml", "cf-shared-secrets.yml")
    end

    private

    def find_or_create_org(name)
      org = client.organization_by_name(name)

      unless org
        invoke :create_org, :name => name
        org = client.organization_by_name(name)
      end
      org
    end

    def find_or_create_space(org, name)
      space = client.space_by_name(name)

      unless space
        invoke :create_space, :organization => org, :name => name
        space = client.space_by_name(org)
      end
      space
    end
  end
end
