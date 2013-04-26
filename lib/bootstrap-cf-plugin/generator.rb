module BootstrapCfPlugin
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
      bosh_target = YAML.load_file(File.join(ENV["HOME"], ".bosh_config"))["target"]
      YAML.load(Net::HTTP.get(URI.parse("#{bosh_target}/info")))["uuid"]
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

    def to_hash
      hash = YAML.load ERB.new(File.read(File.expand_path('../../../templates/cf-aws-stub.yml.erb', __FILE__)), 0, "-%<>").result(binding)
      hash["properties"].merge!(@rds_receipt["deployment_manifest"]["properties"])

      # this is a hack until the ccdb_ng yaml reference is removed from the vpc template
      # (the yaml marshalling will generate a ccdb_ng: *ccdb line)
      hash["properties"]["ccdb_ng"] = hash["properties"]["ccdb"]
      hash
    end

    def save
      File.open("cf-aws.yml", "w+") do |f|
        f.write(YAML.dump(to_hash))
      end
    end
  end
end
