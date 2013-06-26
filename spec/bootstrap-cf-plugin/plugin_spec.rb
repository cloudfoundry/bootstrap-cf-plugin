require 'spec_helper'

describe BootstrapCfPlugin::Plugin do
  let(:client) { fake_client }
  let(:mongodb_token) { 'mongo-secret' }
  let(:mysql_token) { 'mysql-secret' }
  let(:postgresql_token) { 'postgresql-secret' }
  let(:smtp_token) { 'ad_smtp_sendgriddev_token' }
  let(:bootstrap_org) { fake :organization, :name => "bootstrap-org" }
  let(:bootstrap_space) { fake :space, :name => "bootstrap-space" }

  before do
    stub(BootstrapCfPlugin::DirectorCheck).check
    stub(BootstrapCfPlugin::Infrastructure::Aws).bootstrap
    stub(BootstrapCfPlugin::Infrastructure::Aws).generate_stub
    stub(BootstrapCfPlugin::SharedSecretsFile).find_or_create
    stub_invoke :logout
    stub_invoke :login, anything
    stub_invoke :target, anything
    stub_invoke :create_space, anything
    stub_invoke :create_org, anything
    stub_invoke :create_service_auth_token, anything
    stub_client
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
        stub(BootstrapCfPlugin::DirectorCheck).check { raise "some error message" }
        dont_allow(BootstrapCfPlugin::Infrastructure::Aws).bootstrap
        expect {
          subject
        }.to raise_error "some error message"
      end
    end

    it "should invoke AWS.bootstrap when infrastructure is AWS" do
      mock(BootstrapCfPlugin::Infrastructure::Aws).bootstrap.with(nil)
      subject
    end

    it "should use given template file" do
      mock(BootstrapCfPlugin::Infrastructure::Aws).bootstrap.with("test.erb")
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
        called = false
        stub.proxy(described_class).new do |cli|
          stub(cli).invoke(:login, :username => 'user', :password => 'da_password') do
            called = true
            raise CF::UserFriendlyError, "There are no organizations"
          end
          stub(cli).invoke :logout
          stub(cli).invoke :target, anything
          stub(cli).invoke :create_org, anything
          stub(cli).invoke :create_space, anything
          stub(cli).invoke :create_service_auth_token, anything
        end
        exit_code = subject
        called.should be_true
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
      subject
    end

    it "ignores services tokens that already exist" do
      any_instance_of described_class do |cli|
        mock(cli).invoke(:create_service_auth_token, anything) { raise CFoundry::ServiceAuthTokenLabelTaken }
      end
      subject
    end

    context "when the org was created" do
      let(:client) { fake_client :organizations => [bootstrap_org] }

      let(:bootstrap_org) { fake :organization, :name => "bootstrap-org" }

    end

    context "when the org and space were created" do
      let(:client) { fake_client :organizations => [bootstrap_org], :spaces => [bootstrap_space] }

      let(:bootstrap_org) { fake :organization, :name => "bootstrap-org" }
      let(:bootstrap_space) { fake :space, :name => "bootstrap-space" }

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
          stub(BootstrapCfPlugin::DirectorCheck).check { raise "some error message" }
          dont_allow(BootstrapCfPlugin::Infrastructure::Aws).generate_stub
          expect {
            subject
          }.to raise_error "some error message"
        end
      end

      it "should invoke SharedSecretsFile.find_or_create" do
        mock(BootstrapCfPlugin::SharedSecretsFile).find_or_create.with("cf-shared-secrets.yml")
        subject
      end

      it "should invoke AWS.generate_stub when infrastructure is AWS" do
        mock(BootstrapCfPlugin::Infrastructure::Aws).generate_stub.with("cf-aws-stub.yml", "cf-shared-secrets.yml")
        subject
      end
    end

  end
end
