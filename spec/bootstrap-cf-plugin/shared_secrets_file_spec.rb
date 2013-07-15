require "spec_helper"

describe BootstrapCfPlugin::SharedSecretsFile do
  let(:password_length) { 18 }

  let(:filename) { "cf-shared-secrets.yml" }

  around do |example|
    Dir.chdir(Dir.mktmpdir) do
      example.run
    end
  end

  describe "#find_or_create" do
    context "when there is not an existing file" do
      let(:properties) do
        BootstrapCfPlugin::SharedSecretsFile.find_or_create(filename)
        YAML.load_file(filename).fetch("properties")
      end

      let(:secret_params) do
        # non-exhaustive
        [
          properties["uaa"]["scim"]["users"][0].split("|")[1],
          properties["uaa"]["scim"]["users"][1].split("|")[1],
          properties["nats"]["password"],
          properties["cc"]["bulk_api_password"],
          properties["cc"]["db_encryption_key"],
          properties["uaa"]["cc"]["client_secret"]
        ]
      end

      it "fills in every secret field with a password of the right length" do
        secret_params.each do |param|
          param.length.should == password_length
        end
      end

      it "generates a unique password for every secret field" do
        secret_params.should =~ secret_params.uniq
      end
    end

    context "when there is an existing file" do
      it "should not recreate it if it's not empty" do
        File.open filename, "w" do |f|
          f.write("already_here")
        end

        BootstrapCfPlugin::SharedSecretsFile.find_or_create(filename)

        File.read(filename).should == "already_here"
      end

      it "should recreate it if it's empty" do
        FileUtils.touch filename

        BootstrapCfPlugin::SharedSecretsFile.find_or_create(filename)

        File.read(filename).should_not be_empty
      end
    end
  end

  describe "#random_string" do
    it "never includes a pipe character (because UAA uses that as a delimiter)" do
      50.times do
        BootstrapCfPlugin::SharedSecretsFile.random_string.should_not include('|')
      end
    end

    it "never includes any delimiters except - and _" do
      50.times do
        BootstrapCfPlugin::SharedSecretsFile.random_string.should_not include(';')
        BootstrapCfPlugin::SharedSecretsFile.random_string.should_not include('"')
        BootstrapCfPlugin::SharedSecretsFile.random_string.should_not include("'")
      end
    end

    it "warns when words file not found with better error message" do
      stub(Haddock::Password).generate {  raise Haddock::Password::NoWordsError }
      mock(BootstrapCfPlugin::SharedSecretsFile).puts("We can't find your dictionary words file.   Please make sure you have one installed... this is usually part of the wamerican pacakge on your system")
      lambda{BootstrapCfPlugin::SharedSecretsFile.random_string}.should raise_error(SystemExit)
    end
  end
end
