require "bootstrap-cf-plugin"

module BootstrapCfPlugin
  class Plugin < CF::CLI
    def precondition
      # skip all default preconditions
    end


    desc "Bootstrap a CF deployment"
    group :admin
    input :infrastructure, :argument => :required, :desc => "The infrastructure to bootstrap and deploy"
    input :template, :argument => :optional, :desc => "The template file for the CF deployment"
    def bootstrap
      DirectorCheck.check
      infrastructure_class.bootstrap(input[:template])

      invoke :logout
      invoke :target, :url => cloud_controller_url

      login_as_uaa_user
      org = find_or_create_org("bootstrap-org")
      space = find_or_create_space(org, "bootstrap-space")
      login_as_uaa_user
      invoke :target, :url => cloud_controller_url, :organization => org, :space => space

      insert_services_tokens

      puts "All done with bootstrap!"
    end

    desc "Generate a manifest stub"
    group :admin
    input :infrastructure, :argument => :required, :desc => "The infrastructure for which to generate a stub"
    def generate_stub
      DirectorCheck.check
      SharedSecretsFile.find_or_create("cf-shared-secrets.yml")
      infrastructure_class.generate_stub("cf-#{infrastructure}-stub.yml", "cf-shared-secrets.yml")
    end

    private

    def infrastructure
      input[:infrastructure] || raise("Infrastructure must be specified")
    end

    def cf_manifest
      @cf_manifest ||= load_yaml_file("cf-#{infrastructure}.yml")
    end

    def cf_services_manifest
      load_yaml_file("cf-services-#{infrastructure}.yml")
    end

    def uaa_user
      cf_manifest.fetch('properties').fetch('uaa').fetch('scim').fetch('users').first.split("|")
    end

    def uaa_user_login
      uaa_user[0]
    end

    def uaa_user_pw
      uaa_user[1]
    end

    def cloud_controller_url
      cf_manifest.fetch('properties').fetch('cc').fetch('srv_api_uri')
    end

    def login_as_uaa_user
      begin
        invoke :login, :username => uaa_user[0], :password => uaa_user[1]
      rescue CF::UserFriendlyError, /There are no (organizations|spaces)/
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

    def insert_services_tokens
      (tokens_from_jobs(cf_services_manifest.fetch('jobs', []))).each do |gateway_info|
        begin
          invoke :create_service_auth_token, gateway_info
        rescue CFoundry::ServiceAuthTokenLabelTaken => e
          puts "  Don't worry, service token already installed, continuing"
        end
      end
    end

    def find_or_create_org(name)
      org = client.organization_by_name(name)

      unless org
        invoke :create_org, :name => name, :target => false
        org = client.organization_by_name(name)
        puts org.inspect
      end
      org
    end

    def find_or_create_space(org, name)
      space = client.space_by_name(name)

      unless space
        invoke :create_space, :organization => org, :name => name
        space = client.space_by_name(name)
      end
      space
    end
  end
end

def infrastructure_class
  infrastructure_class = infrastructure.to_s.capitalize
  infrastructure_module = ::BootstrapCfPlugin::Infrastructure
  if infrastructure_module.const_defined?(infrastructure_class)
    infrastructure_module.const_get(infrastructure_class)
  else
    raise "Unsupported infrastructure #{infrastructure}"
  end
end

