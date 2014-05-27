require 'rubygems'
require 'fileutils'

require File.join(File.expand_path(File.dirname(__FILE__)), 'XcodeBuilder.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'ParameterStorage.rb')

####################################################################################################
# Builder
####################################################################################################

class AutomationBuilder

  def initialize

    resultPath = "'#{File.dirname(__FILE__)}/../../buildArtifacts/xcodeArtifacts'"
    @builder = XcodeBuilder.new
    @builder.addParameter('configuration','Debug')
    @builder.addEnvironmentVariable('CONFIGURATION_BUILD_DIR',resultPath)
    @builder.addEnvironmentVariable('CONFIGURATION_TEMP_DIR',resultPath)
    @builder.addEnvironmentVariable('UIAUTOMATION_BUILD',true)
    @builder.killSim
  end

  def buildScheme scheme, hardwareID = nil, workspace = nil, coverage = FALSE, skipClean = FALSE

    unless skipClean
      @builder.clean
    end

    directory = Dir.pwd
    unless workspace.nil?
      Dir.chdir(workspace)
    end
  
    preprocessorDefinitions = "$(value) UIAUTOMATION_BUILD=1"
    if hardwareID.nil?
      @builder.addParameter('sdk','iphonesimulator')
      @builder.addParameter('arch','i386')
    else
      @builder.addParameter('arch','armv7')
      @builder.addParameter('destination',"id=#{hardwareID}")
      preprocessorDefinitions = preprocessorDefinitions + " AUTOMATION_UDID=#{hardwareID}"
    end
    
    @builder.addEnvironmentVariable('GCC_PREPROCESSOR_DEFINITIONS',"'#{preprocessorDefinitions}'")
    
    @builder.addParameter('xcconfig',"'#{File.dirname(__FILE__)}/../resources/BuildConfiguration.xcconfig'")
    
    @builder.addParameter('scheme',scheme)
    @builder.run

    Dir.chdir(directory)
  end

end
