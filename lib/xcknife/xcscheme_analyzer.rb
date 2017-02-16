require 'rexml/document'

module XCKnife
  module XcschemeAnalyzer
    extend self

    def extract_environment_variables(xscheme_data)
      ret = {}
      xml_root = REXML::Document.new(xscheme_data).root
      env_elements = xml_root.elements["//EnvironmentVariables"]
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
