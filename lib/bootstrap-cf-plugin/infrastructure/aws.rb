module BootstrapCfPlugin
  module Infrastructure
    class Aws
      DEFAULT_LIGHT_STEMCELL_URL = "http://bosh-jenkins-artifacts.s3.amazonaws.com/last_successful_bosh-stemcell_light.tgz"

      def self.bootstrap(template_file = nil)
        begin
          puts("Checking for release...")
          sh("bosh -n releases | grep -v 'bosh-release'")
          puts("Missing release, creating...")
          sh("git clone http://github.com/cloudfoundry/cf-release #{cf_release_path}") unless Dir.exist?(cf_release_path)
          sh("cd #{cf_release_path} && ./update")
          sh("cd #{cf_release_path} && bosh -n create release --force && bosh -n upload release")
        rescue Exception => e
          raise e unless e.message =~ /releases/
          puts("Using found release")
        end

        begin
          unless ENV.has_key? "BOSH_OVERRIDE_LIGHT_STEMCELL_URL"
            puts("Checking for stemcell...")
            sh("bosh -n stemcells | tail -1 | grep 'No stemcells'")
            puts("Missing stemcell uploading...")
          end
          stemcell_file_name = light_stemcell_url.split("/").last
          sh("cd /tmp && rm -f #{stemcell_file_name} && wget '#{light_stemcell_url}' --no-check-certificate")
          sh("bosh -n upload stemcell /tmp/#{stemcell_file_name}")
        rescue Exception => e
          raise e unless e.message =~ /stemcells/
          puts("Using found stemcell")
        end

        begin
          puts("Checking for a cf deployment...")
          sh("bosh -n deployments | grep -v 'cf-#{generator.name}'")

          puts("Missing deployment, creating...")
          generate_stub
          template_file ||= File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','templates','cf-aws-template.yml.erb'))

          sh("bosh -n deployment cf-aws.yml")
          sh("bosh -n diff #{template_file}")
        rescue Exception => e
          raise e unless e.message =~ /deployments/
          puts("Using found deployment")
        end

        puts("Running bosh deploy...")
        sh("bosh -n deploy")
        begin
          puts "INFO: bootstrap complete"
          sh("bosh -n status")
        end
      end

      def self.generate_stub
        generator.save
      end

      private
      def self.cf_release_path
        '/tmp/cf-release'
      end

      def self.sh(cmd)
        raise "Failed to run: #{cmd}" unless system(cmd)
      end

      def self.light_stemcell_url
        ENV["BOSH_OVERRIDE_LIGHT_STEMCELL_URL"] || DEFAULT_LIGHT_STEMCELL_URL
      end

      def self.generator
        @generator ||= BootstrapCfPlugin::Generator.new("aws_vpc_receipt.yml", "aws_rds_receipt.yml")
      end
    end
  end
end
