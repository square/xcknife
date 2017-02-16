require 'spec_helper'

describe XCKnife::XcschemeAnalyzer do
  let(:scheme) do
    <<eof
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "0720"
   version = "1.3">
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

  it "can parse xcscheme files with EnvironmentVariables" do
    attrs = XCKnife::XcschemeAnalyzer.extract_environment_variables(scheme)
    expect(attrs).to eq("ENABLED_FLAG" => "1")
  end

  it "will return empty hash if no EnvironmentVariables are listed" do
    attrs = XCKnife::XcschemeAnalyzer.extract_environment_variables("<Scheme></Scheme>")
    expect(attrs).to eq({})
  end
end
