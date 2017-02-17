require 'spec_helper'

describe XCKnife::XcschemeAnalyzer do
  include XCKnife::XcschemeAnalyzer

  def scheme(shouldUseLaunchSchemeArgsEnv = true)
    option_str = shouldUseLaunchSchemeArgsEnv ? "YES" : "NO"
    <<eof
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "0720"
   version = "1.3">
   <TestAction shouldUseLaunchSchemeArgsEnv="#{option_str}"/>
   <LaunchAction>
      <EnvironmentVariables>
         <EnvironmentVariable
            key = "ENABLED_FLAG"
            value = "1"
            isEnabled = "YES">
         </EnvironmentVariable>
         <EnvironmentVariable
            key = "DISABLED_FLAG"
            value = "does-not-matter"
            isEnabled = "NO">
         </EnvironmentVariable>
      </EnvironmentVariables>
      <AdditionalOptions>
      </AdditionalOptions>
   </LaunchAction>
</Scheme>
eof
  end

  def scheme_shouldUseLaunchSchemeArgsEnv_equals_to_NO
    scheme(false)
  end


  it "can parse xcscheme files with EnvironmentVariables" do
    attrs = extract_environment_variables(scheme)
    expect(attrs).to eq("ENABLED_FLAG" => "1")
  end

  it "ignores xcscheme EnvironmentVariables if shouldUseLaunchSchemeArgsEnv is NO" do
    attrs = extract_environment_variables(scheme_shouldUseLaunchSchemeArgsEnv_equals_to_NO)
    expect(attrs).to eq({})
  end

  it "will return empty hash if no EnvironmentVariables are listed" do
    attrs = extract_environment_variables("<Scheme></Scheme>")
    expect(attrs).to eq({})
  end

end
