# frozen_string_literal: true

require 'spec_helper'

describe XCKnife::XcschemeAnalyzer do
  include XCKnife::XcschemeAnalyzer

  def environment_variables(suffix)
    <<~XCODEPROJ_SECTION
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
    XCODEPROJ_SECTION
  end

  def scheme(should_use_launch_scheme_args_env)
    option_str = should_use_launch_scheme_args_env ? 'YES' : 'NO'
    test_environment_variables = environment_variables('TEST')
    launch_environment_variables = environment_variables('LAUNCH')
    <<~XCODEPROJ_SECTION
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
    XCODEPROJ_SECTION
  end

  def scheme_should_use_launch_scheme_args_env_equals_to_no
    scheme(false)
  end

  def scheme_should_use_launch_scheme_args_env_equals_to_yes
    scheme(true)
  end

  it 'can parse xcscheme files with EnvironmentVariables' do
    attrs = extract_environment_variables(scheme_should_use_launch_scheme_args_env_equals_to_yes)
    expect(attrs).to eq('ENABLED_FLAG_LAUNCH' => '1')
  end

  it 'ignores xcscheme EnvironmentVariables if shouldUseLaunchSchemeArgsEnv is NO' do
    attrs = extract_environment_variables(scheme_should_use_launch_scheme_args_env_equals_to_no)
    expect(attrs).to eq('ENABLED_FLAG_TEST' => '1')
  end

  it 'will return empty hash if no EnvironmentVariables are listed' do
    attrs = extract_environment_variables('<Scheme></Scheme>')
    expect(attrs).to eq({})
  end
end
