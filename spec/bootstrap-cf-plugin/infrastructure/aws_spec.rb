require 'spec_helper'

describe BootstrapCfPlugin::Infrastructure::Aws do

  let(:cf_release_path) { "/tmp/spec-cf-release" }
  let!(:working_path) do
    Dir.mktmpdir.tap do |path|
      FileUtils.cp asset("aws_receipt.yml"), File.join(path, "aws_vpc_receipt.yml")
      FileUtils.cp asset("rds_receipt.yml"), File.join(path, "aws_rds_receipt.yml")
    end
  end

  before :each do
    FileUtils.rm_rf(cf_release_path)
    any_instance_of(BootstrapCfPlugin::Generator, :director_uuid => "12345-12345-12345")
    stub(described_class).cf_release_path { cf_release_path }
    stub(described_class).sh
  end

  after :each do
    execute_command
  end

  context "::bootstrap" do
    let(:execute_command) do
      Dir.chdir(working_path) do
        BootstrapCfPlugin::Infrastructure::Aws.bootstrap
      end
    end

    describe "releases" do
      context "if release doesn't exist" do
        before do
          mock(described_class).sh("bosh -n releases | grep -v 'bosh-release'") { 0 }
        end

        it 'checkouts the cf-release from github when not present' do
          mock(described_class).sh('git clone http://github.com/cloudfoundry/cf-release /tmp/spec-cf-release')
        end

        it 'does not checkout the cf-release when present' do
          FileUtils.mkdir_p(cf_release_path)
          dont_allow(described_class).sh('git clone http://github.com/cloudfoundry/cf-release /tmp/spec-cf-release')
        end

        it 'updates the cf-release' do
          mock(described_class).sh('cd /tmp/spec-cf-release && ./update')
        end

        it 'creates the cf bosh release' do
          mock(described_class).sh('cd /tmp/spec-cf-release && bosh -n create release --force && bosh -n upload release')
        end
      end

      context "if the release already exists" do
        before do
          stub(described_class).sh("bosh -n releases | grep -v 'bosh-release'") do
            raise "Failed to run: bosh -n releases | grep -v 'bosh-release'"
          end
        end

        it 'skips the cf-release checkouts ' do
          dont_allow(described_class).sh('git clone http://github.com/cloudfoundry/cf-release /tmp/spec-cf-release')
        end

        it 'skips updating the cf-release' do
          dont_allow(described_class).sh('cd /tmp/spec-cf-release && ./update')
        end

        it 'skips creating the cf bosh release' do
          dont_allow(described_class).sh('cd /tmp/spec-cf-release && bosh -n create release --force && bosh -n upload release')
        end
      end
    end

    describe "stemcells" do
      context "if no stemcell URL override is set in the environment" do
        context "if the stemcell doesn't exist" do
          before do
            mock(described_class).sh("bosh -n stemcells | tail -1 | grep 'No stemcells'") { 0 }
          end

          it 'downloads the latest stemcell from S3' do
            mock(described_class).sh("cd /tmp && rm -f last_successful_bosh-stemcell_light.tgz && wget 'http://bosh-jenkins-artifacts.s3.amazonaws.com/last_successful_bosh-stemcell_light.tgz' --no-check-certificate")
          end

          it 'uploads the lastest stemcell' do
            mock(described_class).sh("bosh -n upload stemcell /tmp/last_successful_bosh-stemcell_light.tgz")
          end
        end

        context "if the stemcell does exist" do
          before do
            stub(described_class).sh("bosh -n stemcells | tail -1 | grep 'No stemcells'") do
              raise "Failed to run: bosh -n stemcells | tail -1 | grep 'No stemcells'"
            end
          end

          it 'skips downloading the stemcell from S3' do
            dont_allow(described_class).sh("cd /tmp && rm -f last_successful_bosh-stemcell_light.tgz && wget 'http://bosh-jenkins-artifacts.s3.amazonaws.com/last_successful_bosh-stemcell_light.tgz' --no-check-certificate")
          end

          it 'skips uploading the stemcell' do
            dont_allow(described_class).sh("bosh -n upload stemcell /tmp/last_successful_bosh-stemcell_light.tgz")
          end
        end
      end

      context "if a stemcell URL override is set in the environment" do
        before(:all) do
          ENV["BOSH_OVERRIDE_LIGHT_STEMCELL_URL"] = "http://stemcells-r-us.com/stemcell.tgz"
        end

        after(:all) do
          ENV.delete "BOSH_OVERRIDE_LIGHT_STEMCELL_URL"
        end

        it 'downloads the stemcell at the given URL' do
          mock(described_class).sh("cd /tmp && rm -f stemcell.tgz && wget 'http://stemcells-r-us.com/stemcell.tgz' --no-check-certificate")
        end

        it 'uploads the latest stemcell' do
          mock(described_class).sh("bosh -n upload stemcell /tmp/stemcell.tgz")
        end
      end
    end

    describe "deployments" do
      context "if the deployment doesn't exist" do
        before do
          stub(described_class).sh("bosh -n deployments | grep -v 'cf-deployment'") { 0 }
        end

        it 'generates the manifest file - cf-aws.yml' do
          File.should exist(File.join(working_path, "aws_vpc_receipt.yml"))
          execute_command
          File.should exist(File.join(working_path, "cf-aws.yml"))
        end

        it 'applies the template to the manifest file with bosh diff' do
          templates_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'templates'))
          mock(described_class).sh("bosh -n diff #{templates_dir}/cf-aws-template.yml.erb")
        end

        it 'sets the bosh deployment' do
          mock(described_class).sh('bosh -n deployment cf-aws.yml')
        end
      end

      context "if the deployment does exist" do
        before do
          fake_generator = stub(stub!.save.subject).name { "deployment" }
          stub(described_class).generator { fake_generator }
          stub(described_class).sh("bosh -n deployments | grep -v 'cf-deployment'") do
            raise "Failed to run: bosh -n deployments | grep -v 'cf-deployment'"
          end
        end

        it 'skips generating the manifest file - cf-aws.yml' do
          dont_allow(BootstrapCfPlugin::Generator).new
        end

        it 'skips appling the template to the manifest file with bosh diff' do
          templates_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'templates'))
          dont_allow(described_class).sh("bosh -n diff #{templates_dir}/cf-aws-template.yml.erb")
        end

        it 'skips setting the bosh deployment' do
          dont_allow(described_class).sh('bosh -n deployment cf-aws.yml')
        end
      end
    end

    it 'does the bosh deploy' do
      mock(described_class).sh('bosh -n deploy')
    end
  end

  context "::bootstrap template file" do
    let(:template_file) { "template.erb" }
    let(:execute_command) do
      Dir.chdir(working_path) do
        BootstrapCfPlugin::Infrastructure::Aws.bootstrap template_file
      end
    end

    before do
      stub(described_class).sh("bosh -n deployments | grep -v 'cf-deployment'") { 0 }
    end

    it 'applies the template given with bosh diff' do
      mock(described_class).sh("bosh -n diff template.erb")
    end
  end
end
