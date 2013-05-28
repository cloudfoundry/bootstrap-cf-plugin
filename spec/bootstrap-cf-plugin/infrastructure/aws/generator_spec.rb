require 'spec_helper'
require "bootstrap-cf-plugin/infrastructure/aws/generator"

describe BootstrapCfPlugin::Infrastructure::Aws::Generator do
  let(:aws_receipt_file) { asset("aws/aws_receipt.yml") }
  let(:rds_receipt_file) { asset("aws/rds_receipt.yml") }
  subject do
    BootstrapCfPlugin::Infrastructure::Aws::Generator.new(aws_receipt_file, rds_receipt_file)
  end

  describe "#save" do
    let(:generated_manifest) do
      Dir.chdir("/tmp") do
        subject.save('cf-aws.yml', upstream_manifest)
        YAML.load_file('cf-aws.yml')
      end
    end

    before do
      mock(subject).director_uuid { "12345-12345-12345" }
    end

    context "when no upstream manifest is provided" do
      let(:upstream_manifest) { nil }

      it "generates the expected YAML output" do
        generated_manifest.should == YAML.load_file(asset("aws/expected_cf_stub.yml"))
      end

      it 'gets both CF and Services subnets' do
        generated_manifest["properties"]["template_only"]["aws"]["subnet_ids"].should == {
          "services1"=>"subnet-80709g",
          "cf1"=>"subnet-4bdf6c27"
        }
      end
    end

    context "when an upstream manifest is provided" do
      let(:upstream_manifest) { asset("shared_manifest.yml") }

      it "includes properties from that manifest" do
        generated_manifest.should == YAML.load_file(asset("aws/expected_cf_stub_with_secrets.yml"))
      end

      it 'gets both CF and Services subnets' do
        generated_manifest["properties"]["template_only"]["aws"]["subnet_ids"].should == {
          "services1"=>"subnet-80709g",
          "cf1"=>"subnet-4bdf6c27"
        }
      end
    end
  end

  it "allows access to all of the subnets" do
    subject.subnet_id('cf1').should == 'subnet-4bdf6c27'
    subject.subnet_id('bosh1').should == 'subnet-4bdf6c26'
    subject.subnet_id('other').should == 'subnet-xxxxxxxx'
  end

  describe "manifest_stub" do
    let(:manifest_name) { "some-manifest.yml"}

    it "sets the stub name" do
      subject.manifest_stub(manifest_name).should match(/templates\/some-manifest-stub.yml.erb$/)
    end
  end
end
