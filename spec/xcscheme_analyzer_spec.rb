require 'spec_helper'

describe XCKnife::XcschemeAnalyzer do
  include XCKnife::XcschemeAnalyzer

  def environment_variables(suffix)
<<eof
<EnvironmentVariables>
   <EnvironmentVariable
      key = "ENABLED_FLAG_#{suffix}"
      value = "1"
      isEnabled = "YES">
   </EnvironmentVariable>
   <EnvironmentVariable
      key = "DISABLED_FLAG_#{suffix}"
      value = "does-not-matter"
      isEnabled = "NO">
   </EnvironmentVariable>
</EnvironmentVariables>
eof
  end

  def scheme(shouldUseLaunchSchemeArgsEnv)
    option_str = shouldUseLaunchSchemeArgsEnv ? "YES" : "NO"
    test_environment_variables = environment_variables("TEST")
    launch_environment_variables = environment_variables("LAUNCH")
    <<eof
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "0720"
   version = "1.3">
   <TestAction shouldUseLaunchSchemeArgsEnv="#{option_str}">
    #{test_environment_variables}
   </TestAction>
   <LaunchAction>
      #{launch_environment_variables}
      <AdditionalOptions>
      </AdditionalOptions>
   </LaunchAction>
</Scheme>
eof
  end

  def scheme_shouldUseLaunchSchemeArgsEnv_equals_to_NO
    scheme(false)
  end

  def scheme_shouldUseLaunchSchemeArgsEnv_equals_to_YES
    scheme(true)
  end


  it "can parse xcscheme files with EnvironmentVariables" do
    attrs = extract_environment_variables(scheme_shouldUseLaunchSchemeArgsEnv_equals_to_YES)
    expect(attrs).to eq("ENABLED_FLAG_LAUNCH" => "1")
  end

  it "ignores xcscheme EnvironmentVariables if shouldUseLaunchSchemeArgsEnv is NO" do
    attrs = extract_environment_variables(scheme_shouldUseLaunchSchemeArgsEnv_equals_to_NO)
    expect(attrs).to eq("ENABLED_FLAG_TEST" => "1")
  end

  it "will return empty hash if no EnvironmentVariables are listed" do
    attrs = extract_environment_variables("<Scheme></Scheme>")
    expect(attrs).to eq({})
  end

end
