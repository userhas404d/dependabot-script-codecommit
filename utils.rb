# frozen_string_literal: true

require "yaml"

def fetch_update_configs(input)
  YAML.safe_load(input).fetch("update_configs")
end

def validate_package_manager(package_manager)
  # convert dependabot config package manager syntax to expected format
  # https://dependabot.com/docs/config-file/
  if package_manager.include? ":modules"
    "go_modules"
  elsif package_manager.include? ":"
    package_manager.split(":")[1]
  else
    package_manager
  end
end

def process_config(config_contents)
  configs = fetch_update_configs(config_contents)
  configs.each do |config|
    config["package_manager"] =
      validate_package_manager(config["package_manager"])
  end
end
