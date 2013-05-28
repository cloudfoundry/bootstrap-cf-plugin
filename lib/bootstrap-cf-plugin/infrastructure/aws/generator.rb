class BootstrapCfPlugin::Infrastructure::Aws
  class Generator
    def initialize(aws_receipt_file, rds_receipt_file)
      @aws_receipt = load_yaml_file(aws_receipt_file)
      @rds_receipt = load_yaml_file(rds_receipt_file)
      @aws_request = @aws_receipt["original_configuration"]
    end

    def name
      @aws_request["name"]
    end

    def domain
      @aws_receipt["vpc"]["domain"]
    end

    def static_ips(name)
      @aws_receipt["elastic_ips"][name]["ips"]
    end

    def director_uuid
      bosh_config = ENV['BOSH_CONFIG'].to_s.empty? ? File.join(ENV["HOME"], ".bosh_config") : ENV['BOSH_CONFIG']
      YAML.load_file(bosh_config)["target_uuid"] || raise("Cannot get UUID from BOSH config #{bosh_config}, make sure you've targeted and logged in")
    end

    def micro_ip
      @aws_receipt["elastic_ips"]["micro"]["ips"][0]
    end

    def availability_zone
      @aws_request["vpc"]["subnets"]["cf1"]["availability_zone"]
    end

    def subnet_id(subnet_name)
      @aws_receipt["vpc"]["subnets"][subnet_name]
    end

    def aws_access_key_id
      @aws_receipt["aws"]["access_key_id"]
    end

    def aws_secret_access_key
      @aws_receipt["aws"]["secret_access_key"]
    end

    def manifest_stub(manifest_name)
      manifest_stub_file = manifest_name.gsub(/(.*)\.yml$/, '\1-stub.yml.erb')
      File.join(templates_dir, manifest_stub_file)
    end

    def save(manifest_name, upstream_manifest)
      File.open(manifest_name, "w+") do |f|
        f.write(YAML.dump(to_hash(upstream_manifest)))
      end
    end

    private

    def templates_dir
      File.expand_path("../../../../../templates", __FILE__)
    end

    def to_hash(upstream_manifest)
      manifest_stub = File.join(templates_dir, "cf-aws-stub.yml.erb")
      hash = YAML.load ERB.new(File.read(manifest_stub)).result(binding)
      hash["properties"].merge!(@rds_receipt["deployment_manifest"]["properties"])

      if upstream_manifest
        hash["properties"].merge!(load_yaml_file(upstream_manifest)["properties"])
      end

      # this is a hack until the ccdb_ng yaml reference is removed from the vpc template
      # (the yaml marshalling will generate a ccdb_ng: *ccdb line)
      hash["properties"]["ccdb_ng"] = hash["properties"]["ccdb"]
      hash
    end
  end
end
