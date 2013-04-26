require 'spec_helper'

describe BootstrapCfPlugin::Generator do
  let(:aws_receipt_file) { asset 'aws_receipt.yml' }
  let(:rds_receipt_file) { asset 'rds_receipt.yml' }
  subject { BootstrapCfPlugin::Generator.new(aws_receipt_file, rds_receipt_file) }

  it "should generate the expected YAML output" do
    mock(subject).director_uuid { "12345-12345-12345" }
    Dir.chdir("/tmp") do
      subject.save
      YAML.load_file('cf-aws.yml').should == YAML.load_file(asset 'expected_cf_stub.yml')
    end
  end

  it "should allow access to all of the subnets" do
    subject.subnet_id('cf1').should == 'subnet-4bdf6c27'
    subject.subnet_id('bosh1').should == 'subnet-4bdf6c26'
    subject.subnet_id('other').should == 'subnet-xxxxxxxx'
  end
end
