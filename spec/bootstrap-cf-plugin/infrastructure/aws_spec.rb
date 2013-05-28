require 'spec_helper'

describe BootstrapCfPlugin::Infrastructure::Aws do
  let!(:temp_dir) { Dir.mktmpdir }
  let(:release_name) { 'cf-release' }
  let(:cf_release_path) { File.join(Dir.tmpdir, release_name) }
  let(:manifest_name) { "#{release_name.gsub('-release', '')}-aws.yml" }

  before do
    any_instance_of(BootstrapCfPlugin::Generator, :director_uuid => "12345-12345-12345")
    stub(described_class).sh
    stub(described_class).sh_output
    stub(described_class).puts
    stub(described_class).cf_release_path { |name| cf_release_path }

    FileUtils.cp asset("aws_receipt.yml"), File.join(temp_dir, "aws_vpc_receipt.yml")
    FileUtils.cp asset("rds_receipt.yml"), File.join(temp_dir, "aws_rds_receipt.yml")
  end

  after do
    FileUtils.remove_entry_secure(temp_dir)
    FileUtils.rm_rf(cf_release_path)
  end

  def clone_release
    FileUtils.mkdir_p(File.join(cf_release_path, "config"))
  end

  describe "deploy_release" do
    subject do
      Dir.chdir(temp_dir) do
        BootstrapCfPlugin::Infrastructure::Aws.deploy_release release_name, manifest_name, nil, nil
      end
    end

    it "all of the subnets inside the generated yml" do
      subject
      output = YAML.load_file(File.join(temp_dir, manifest_name))
      output["properties"]["template_only"]["aws"]["subnet_ids"].should have(2).items
    end

    it "does the bosh deploy" do
      mock(described_class).sh('bosh -n deploy')
      subject
    end

    describe "releases" do
      it 'checkouts the cf-release from github when not present' do
        stub(Dir).tmpdir { temp_dir }
        mock(described_class).sh("git clone -b release-candidate http://github.com/cloudfoundry/cf-release #{cf_release_path}") { clone_release }
        subject
      end

      it 'updates the cf-release' do
        mock(described_class).update_release(cf_release_path)
        subject
      end

      it 'creates the cf bosh release' do
        mock(described_class).sh("cd #{cf_release_path} && bosh -n create release --force")
        subject
      end

      it 'uploads the cf bosh release' do
        mock(described_class).sh_output("cd #{cf_release_path} && bosh -n upload release --rebase")
        subject
      end

      it 'continues if there are no job and package changes' do
        command = "cd #{cf_release_path} && bosh -n upload release --rebase"
        error = 'Error 100: Rebase is attempted without any job or package changes'

        mock(described_class).sh_output(command) { raise RuntimeError.new(error) }
        expect { subject }.not_to raise_error
      end
    end

    describe "deployments" do
      it 'generates the manifest file - cf-aws.yml' do
        File.should exist(File.join(temp_dir, "aws_vpc_receipt.yml"))
        subject
        File.should exist(File.join(temp_dir, "cf-aws.yml"))
      end

      it 'applies the template to the manifest file with bosh diff' do
        aws_template = File.join(Dir.tmpdir, "cf-release", "templates", "cf-aws-template.yml.erb")
        mock(described_class).sh("bosh -n diff #{aws_template}")
        subject
      end

      it 'sets the bosh deployment' do
        mock(described_class).sh('bosh -n deployment cf-aws.yml')
        subject
      end
    end

  end

  describe "#upload_stemcell" do
    subject do
      Dir.chdir(temp_dir) do
        BootstrapCfPlugin::Infrastructure::Aws.upload_stemcell
      end
    end

    let(:stemcell_file) { "last_successful_bosh-stemcell-aws_light.tgz" }
    let(:bucket_url) { "http://bosh-jenkins-artifacts.s3.amazonaws.com" }

    context "if no stemcell URL override is set in the environment" do
      context "if the stemcell doesn't exist" do
        before do
          mock(described_class).sh("bosh -n stemcells | tail -1 | grep 'No stemcells'") { 0 }
        end

        it 'downloads the latest stemcell from S3' do
          mock(described_class).sh("cd /tmp && rm -f #{stemcell_file} && wget '#{bucket_url}/#{stemcell_file}' --no-check-certificate")
          subject
        end

        it 'uploads the lastest stemcell' do
          mock(described_class).sh("bosh -n upload stemcell /tmp/#{stemcell_file}")
          subject
        end
      end

      context "if the stemcell does exist" do
        before do
          stub(described_class).sh("bosh -n stemcells | tail -1 | grep 'No stemcells'") do
            raise "Failed to run: bosh -n stemcells | tail -1 | grep 'No stemcells'"
          end
        end

        it 'skips downloading the stemcell from S3' do
          dont_allow(described_class).sh("cd /tmp && rm -f #{stemcell_file} && wget '#{bucket_url}/#{stemcell_file}' --no-check-certificate")
          subject
        end

        it 'skips uploading the stemcell' do
          dont_allow(described_class).sh("bosh -n upload stemcell /tmp/#{stemcell_file}")
          subject
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
        subject
      end

      it 'uploads the latest stemcell' do
        mock(described_class).sh("bosh -n upload stemcell /tmp/stemcell.tgz")
        subject
      end
    end
  end

  describe "bootstrap" do
    let(:template_file) { nil }

    subject do
      Dir.chdir(temp_dir) do
        BootstrapCfPlugin::Infrastructure::Aws.bootstrap template_file
      end
    end

    it "uploads stemcell" do
      mock(described_class).upload_stemcell
      subject
    end

    it "deploys release for cf-release and cf-services-release" do
      mock(described_class).deploy_release("cf-release", "cf-aws.yml", "cf-shared-secrets.yml", template_file)
      mock(described_class).deploy_release("cf-services-release", "cf-services-aws.yml", "cf-shared-secrets.yml", template_file)
      subject
    end

    it "creates a shared secret file" do
      subject
      File.should be_exists("#{temp_dir}/cf-shared-secrets.yml")
    end

    context "with custom template file" do
      let(:template_file) { "template.erb" }

      it 'applies the template given with bosh diff' do
        mock(described_class).sh("bosh -n diff template.erb")
        subject
      end
    end
  end
end
