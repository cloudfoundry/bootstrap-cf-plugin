require "haddock"

module BootstrapCfPlugin
  class SharedSecretsFile
    PASSWORD_LENGTH = 18
    def self.random_string
      Haddock::Password.delimiters = "-_"
      Haddock::Password.generate(PASSWORD_LENGTH)
    rescue Haddock::Password::NoWordsError
      puts("We can't find your dictionary words file.   Please make sure you have one installed... this is usually part of the wamerican pacakge on your system")
      exit(1)
    end

    def self.find_or_create(filename)
      template_path = File.join(File.dirname(__FILE__), "..", "..", "templates", "cf-shared-secrets.yml.erb")
      unless File.exists?(filename) && !File.read(filename).empty?
        File.open(filename, "w") do |f|
          f.write ERB.new(File.read(template_path)).result(binding)
        end
      end
    end
  end
end
