require 'rexml/document'

module XCKnife
  module XcschemeAnalyzer
    extend self

    def extract_environment_variables(xscheme_data)
      ret = {}
      xml_root = REXML::Document.new(xscheme_data).root


      action = xml_root.elements["//TestAction"]
      return ret if action.nil?
      if action.attributes['shouldUseLaunchSchemeArgsEnv'] == "YES"
        action = xml_root.elements["//LaunchAction"]
      end
      return ret if action.nil?
      env_elements = action.elements[".//EnvironmentVariables"]
      return ret if env_elements.nil?
      env_elements.elements.each do |e|
        attrs = e.attributes
        if attrs["isEnabled"] == "YES"
          ret[attrs["key"]] = attrs["value"]
        end
      end
      ret
    end
  end
end
