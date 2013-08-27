require 'spec_helper'

describe BootstrapCfPlugin::Plugin do
  let(:client) { fake_client }
  let(:mongodb_token) { 'mongo-secret' }
  let(:mysql_token) { 'mysql-secret' }
  let(:postgresql_token) { 'postgresql-secret' }
  let(:smtp_token) { 'ad_smtp_sendgriddev_token' }
  let(:bootstrap_org) { FactoryGirl.build(:organization, name: "bootstrap-org") }
  let(:bootstrap_space) { FactoryGirl.build(:space, name: "bootstrap-space") }

  before do
    BootstrapCfPlugin::DirectorCheck.stub(:check)
    BootstrapCfPlugin::Infrastructure::Aws.stub(:bootstrap)
    BootstrapCfPlugin::Infrastructure::Aws.stub(:generate_stub)
    BootstrapCfPlugin::SharedSecretsFile.stub(:find_or_create)
    stub_invoke :logout
    stub_invoke :login, anything
    stub_invoke :target, anything
    stub_invoke :create_space, anything
    stub_invoke :create_org, anything
    stub_invoke :create_service_auth_token, anything
    #stub_client
  end

  def fake_client(*args)
    client = FactoryGirl.build(:client)
    client.stub(*args)
    client
  end

  def services_manifest_hash
    {
      "jobs" => [
        {
          "properties" => {
            "mongodb_gateway" => {
              "token" => mongodb_token
            },
            "mysql_gateway" => {
              "token" => mysql_token
            }
          }
        },
        {
          "properties" => {
            "rabbit_gateway" => {
              "token" => "rabbit_secret"
            },
            "rds_mysql_gateway" => {
              "token" => "rds_secret"
            },
          }
        },
        {
          "properties" => {
            "postgresql_gateway" => {
              "token" => postgresql_token
            }
          }
        }
      ],
        "properties" => {
        'uaa' => {
          'scim' => {
            'users' => ["user|da_password"]
          }
        }
      }
    }
  end

  def manifest_hash
    {
      "jobs" => [
      ],
        "properties" => {
        "cc" => {
          "srv_api_uri" => "http://example.com"
        },
        'uaa' => {
          'scim' => {
            'users' => ["user|da_password"]
          }
        }
      }
    }
  end

  around do |example|
    Dir.chdir(Dir.mktmpdir) do
      File.open("cf-aws.yml", "w") do |w|
        w.write(YAML.dump(manifest_hash))
      end

      File.open("cf-services-aws.yml", "w") do |w|
        w.write(YAML.dump(services_manifest_hash))
      end

      example.run
    end
  end

  context "when the infrastructure is not AWS" do
    subject { cf %W[bootstrap awz] }

    it "should throw an error when the infrastructure is not AWS" do
      expect {
        subject
      }.to raise_error("Unsupported infrastructure awz")
    end
  end

  context "when the infrastructure is AWS" do
    subject { cf %W[bootstrap aws] }

    describe "verifying access to director" do
      it "should blow up if unable to get director status" do
        BootstrapCfPlugin::DirectorCheck.should_receive(:check).
          and_raise("some error message")
        BootstrapCfPlugin::Infrastructure::Aws.should_not_receive(:bootstrap)
        expect {
          subject
        }.to raise_error "some error message"
      end
    end

    it "should invoke AWS.bootstrap when infrastructure is AWS" do
      BootstrapCfPlugin::Infrastructure::Aws.should_receive(:bootstrap).with(nil)
      subject
    end

    it "should use given template file" do
      BootstrapCfPlugin::Infrastructure::Aws.should_receive(:bootstrap).with("test.erb")
      cf %W[bootstrap aws test.erb]
    end

    it 'targets the CF client' do
      mock_invoke :target, :url => "http://example.com"
      subject
    end

    it 'logs out and logs in into the CF' do
      mock_invoke :logout
      mock_invoke :login, :username => 'user', :password => 'da_password'
      subject
    end

    context "when the organization does not exist" do

      it 'does not crash on login, due to organization missing' do
        cli = double("CLI", :input= => nil)
        cli.should_receive(:invoke).
          with(:login, :username => 'user', :password => 'da_password').
          and_raise(CF::UserFriendlyError, "There are no organizations")

        described_class.stub(:new).and_return(cli)
        cli.stub(:execute)
        cli.stub(:invoke).with(:logout)
        cli.stub(:invoke).with(:login)
        cli.stub(:invoke).with(:target, anything)
        cli.stub(:invoke).with(:create_org, anything)
        cli.stub(:invoke).with(:create_space, anything)
        cli.stub(:invoke).with(:create_service_auth_token, anything)

        exit_code = subject
        expect(error_output).not_to say("There are no organizations")
        exit_code.should == 0
      end


      it 'CF creates an Organization' do
        mock_invoke :create_org, :name => "bootstrap-org"
        subject
      end

      it "creates a space" do
        mock_invoke :create_space, hash_including(name: "bootstrap-space")
        subject
      end
    end

    context "when the organization already exists" do
      let!(:client) { fake_client :organizations => [bootstrap_org] }

      it "does not create it again" do
        dont_allow_invoke :create_org, anything
        subject
      end

      context "when the space does not exist" do
        it "creates a space inside the existing org" do
          mock_invoke :create_space, :organization => bootstrap_org, :name => "bootstrap-space"
          subject
        end
      end

      context "when the space already exists" do
        let!(:client) { fake_client :organizations => [bootstrap_org], :spaces => [bootstrap_space] }

        it "does not create it again" do
          dont_allow_invoke :create_space, anything
          subject
        end
      end
    end

    it "invokes create-service-token for each service" do
      mock_invoke :create_service_auth_token, :label => 'mongodb', :provider => 'core', :token => mongodb_token
      mock_invoke :create_service_auth_token, :label => 'mysql', :provider => 'core', :token => mysql_token
      mock_invoke :create_service_auth_token, :label => 'postgresql', :provider => 'core', :token => postgresql_token
      mock_invoke :create_service_auth_token, :label => 'rabbitmq', :provider => 'core', :token => "rabbit_secret"
      mock_invoke :create_service_auth_token, :label => 'rds-mysql', :provider => 'aws', :token => "rds_secret"

      subject
    end

    it "ignores services tokens that already exist" do
      described_class.any_instance.should_receive(:invoke).
        with(:create_service_auth_token, anything).
        and_raise(CFoundry::ServiceAuthTokenLabelTaken)
      subject
    end

    context "when the org and space were created" do
      let(:client) { FactoryGirl.build(:client, :organizations => [bootstrap_org], :spaces => [bootstrap_space]) }

      let(:bootstrap_org) { FactoryGirl.build(:user, name: "bootstrap-org")  }
      let(:bootstrap_space) { FactoryGirl.build(:space, name: "bootstrap-space") }

      it 'CF targets the org and space' do
        mock_invoke :target, :url => "http://example.com", :organization => bootstrap_org, :space => bootstrap_space
        subject
      end
    end
  end

  describe "generate_stub" do
    context "when the infrastructure is AWS" do
      subject { cf %W[generate-stub aws] }

      describe "verifying access to director" do
        it "should blow up if unable to get director status" do
          BootstrapCfPlugin::DirectorCheck.should_receive(:check).
            and_raise("some error message")
          BootstrapCfPlugin::Infrastructure::Aws.should_not_receive(:generate_stub)
          expect {
            subject
          }.to raise_error "some error message"
        end
      end

      it "should invoke SharedSecretsFile.find_or_create" do
        BootstrapCfPlugin::SharedSecretsFile.should_receive(:find_or_create).
          with("cf-shared-secrets.yml")
        subject
      end

      it "should invoke AWS.generate_stub when infrastructure is AWS" do
        BootstrapCfPlugin::Infrastructure::Aws.should_receive(:generate_stub).
          with("cf-aws-stub.yml", "cf-shared-secrets.yml")
        subject
      end
    end

  end
end
