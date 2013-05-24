module BootstrapCfPlugin
  module Infrastructure
    class Aws
      DEFAULT_LIGHT_STEMCELL_URL = "http://bosh-jenkins-artifacts.s3.amazonaws.com/last_successful_bosh-stemcell-aws_light.tgz"

      def self.bootstrap(template_file = nil)
        upload_stemcell
        SharedSecretsFile.find_or_create("cf-shared-secrets.yml")
        deploy_release("cf-release", "cf-aws.yml", "cf-shared-secrets.yml", template_file)
        deploy_release("cf-services-release", "cf-services-aws.yml", "cf-shared-secrets.yml", template_file)

        puts "INFO: bootstrap complete"
        sh("bosh -n status")
      end

      def self.deploy_release(release_name, manifest_name, upstream_manifest, template_file)
        cf_release_path = cf_release_path(release_name)
        git_url = "http://github.com/cloudfoundry/#{release_name}"

        puts("Creating release #{release_name}")
        puts "git clone -b release-candidate #{git_url} #{cf_release_path}"

        sh("git clone -b release-candidate #{git_url} #{cf_release_path}") unless Dir.exist?(cf_release_path)
        dev_config_path = File.join(cf_release_path, "config", "dev.yml")
        unless File.exists?(dev_config_path)
          File.open(dev_config_path, "w") { |f| f.write("---\ndev_name: #{release_name}") }
        end

        prepare_release(cf_release_path)

        puts("Creating deployment manifest #{manifest_name}")
        generate_stub(manifest_name, upstream_manifest)
        template_file ||= File.join(cf_release_path, 'templates', 'cf-aws-template.yml.erb')

        sh("bosh -n deployment #{manifest_name}")
        sh("bosh -n diff #{template_file}")

        puts("Running bosh deploy...")
        sh("bosh -n deploy")
      end

      def self.update_release(path)
        sh "cd #{path} && ./update"
      end

      def self.prepare_release(path)
        update_release path
        sh("cd #{path} && bosh -n create release --force")
        begin
          puts sh_output("cd #{path} && bosh -n upload release --rebase")
        rescue RuntimeError => e
          check_release_error e
        end
      end

      def self.upload_stemcell
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
      end

      def self.generate_stub(manifest_name = "cf-aws.yml", upstream_manifest = nil)
        generator.save(manifest_name, upstream_manifest)
      end

      private

      def self.cf_release_path(release_name)
        File.join(Dir.tmpdir, release_name)
      end

      def self.sh(cmd)
        raise "Failed to run: #{cmd}" unless system(cmd)
      end

      def self.sh_output(cmd)
        output = `#{cmd}`
        unless $?.success?
          raise "Failed to run: #{cmd}\n\nOutput:\n\n#{output}"
        end
        output
      end

      def self.light_stemcell_url
        ENV["BOSH_OVERRIDE_LIGHT_STEMCELL_URL"] || DEFAULT_LIGHT_STEMCELL_URL
      end

      def self.generator
        @generator ||= BootstrapCfPlugin::Generator.new("aws_vpc_receipt.yml", "aws_rds_receipt.yml")
      end

      def self.check_release_error(e)
        case e.message
          when /Rebase is attempted without any job or package changes/
            puts e.message
            puts 'Skipping upload release. No job or package changes.'
          when /upload release/
            puts e.message
            puts 'Using existing release'
          else
            raise
        end
      end

    end
  end
end
