require 'spec_helper'

command BootstrapCfPlugin::Plugin do
  let(:client) { fake_client }
  let(:mongodb_token) { 'mongo-secret' }
  let(:mysql_token) { 'mysql-secret' }
  let(:postgresql_token) { 'postgresql-secret' }
  let(:smtp_token) { 'ad_smtp_sendgriddev_token' }


  before do
    stub(BootstrapCfPlugin::DirectorCheck).check
    stub(BootstrapCfPlugin::Infrastructure::Aws).bootstrap

    stub_invoke :logout
    stub_invoke :login, anything
    stub_invoke :target, anything
    stub_invoke :create_space, anything
    stub_invoke :create_org, anything
    stub_invoke :create_service_auth_token, anything
  end


  def manifest_hash
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

    it 'CF creates an Organization and a Space' do
      mock_invoke :create_org, :name => "bootstrap-org"
      subject
    end

    it "invokes create-service-token for each service" do
      mock_invoke :create_service_auth_token, :label => 'mongodb', :provider => 'core', :token => mongodb_token
      mock_invoke :create_service_auth_token, :label => 'mysql', :provider => 'core', :token => mysql_token
      mock_invoke :create_service_auth_token, :label => 'postgresql', :provider => 'core', :token => postgresql_token
      mock_invoke :create_service_auth_token, :label => 'smtp', :provider => 'sendgrid-dev', :token => smtp_token
      subject
    end

    context "when the org was created" do
      let(:client) { fake_client :organizations => [bootstrap_org] }

      let(:bootstrap_org) { fake :organization, :name => "bootstrap-org" }

      it 'CF creates a Space' do
        mock_invoke :create_space, :organization => bootstrap_org, :name => "bootstrap-space"
        subject
      end
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
end
