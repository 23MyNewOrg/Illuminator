require 'rubygems'
require 'fileutils'
require 'find'
require 'pathname'
require 'json'

require File.join(File.expand_path(File.dirname(__FILE__)), 'InstrumentsRunner.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'JavascriptRunner.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'XcodeUtils.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'BuildArtifacts.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'TestSuite.rb')

require File.join(File.expand_path(File.dirname(__FILE__)), 'listeners/FullOutput.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'listeners/TestListener.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'listeners/SaltinelAgent.rb')
#TODO: listener that saves the console log

####################################################################################################
# runner
####################################################################################################


# responsibilities:
#  - convert combined settings hash into individual class settings
#  - prepare javascript config, and start instruments
#  - process any crashes
#  - run coverage
class AutomationRunner
  include SaltinelAgentEventSink
  include TestListenerEventSink

  attr_accessor :appName
  attr_accessor :workspace

  attr_reader :instrumentsRunner
  attr_reader :javascriptRunner

  def initialize
    @crashPath         = "#{ENV['HOME']}/Library/Logs/DiagnosticReports"
    @testDefs          = nil
    @testSuite         = nil
    @currentTest       = nil
    @javascriptRunner  = JavascriptRunner.new
    @instrumentsRunner = InstrumentsRunner.new

    @instrumentsRunner.addListener("consoleoutput", FullOutput.new)
  end


  def cleanup
    # start a list of what to remove
    dirsToRemove = [@crashPath]

    # FIXME: this should probably get moved to instrument runner
    # keys to the methods of the BuildArtifacts singleton that we want to remove
    buildArtifactKeys = [:crashReports, :instruments, :objectFiles, :coverageReportFile,
                         :junitReportFile, :illuminatorJsRunner, :illuminatorJsEnvironment, :illuminatorConfigFile]
    # get the directories without creating them (the 'true' arg), add them to our list
    buildArtifactKeys.each do |key|
      dir = BuildArtifacts.instance.method(key).call(true)
      dirsToRemove << dir
    end

    # remove directories in the list
    dirsToRemove.each do |dir|
      puts "AutomationRunner cleanup: removing #{dir}"
      FileUtils.rmtree dir
    end

    # run cleanups for variables we own
    @instrumentsRunner.cleanup
    # TODO: @javascriptRunner cleanup?

  end


  def saltinelAgentGotScenarioDefinitions jsonPath
    return unless @testDefs.nil?
    rawDefs = JSON.parse( IO.read(jsonPath) )

    # save test defs for use later (as lookups)
    @testDefs = {}
    rawDefs["scenarios"].each { |scen| @testDefs[scen["title"]] = scen }
  end


  def saltinelAgentGotScenarioList jsonPath
    return unless @testSuite.nil?
    rawList = JSON.parse( IO.read(jsonPath) )

    # create a test suite, and add test cases to it.  look up class names from test defs
    @testSuite = TestSuite.new
    rawList["scenarioNames"].each do |n|
      testFileName = @testDefs[n]["inFile"]
      testFnName   = @testDefs[n]["definedBy"]
      className    = testFileName.sub(".", "_") + "." + testFnName
      @testSuite.addTestCase(className, n)
    end
  end


  def testListenerGotTestStart name
    @testSuite[@currentTest].error "ILLUMINATOR FAILURE TO LISTEN" unless @currentTest.nil?
    @testSuite[name].start!
    @currentTest = name
  end

  def testListenerGotTestPass name
    puts "ILLUMINATOR FAILURE TO SORT TESTS".red unless name == @currentTest
    @testSuite[name].pass!
    @currentTest = nil
  end

  def testListenerGotTestFail message
    puts "ILLUMINATOR FAILURE TO LISTEN 2".red if @currentTest.nil?
    return if message == "The target application appears to have died" # assume a crash report exists!!!
    @testSuite[@currentTest].fail message
    @currentTest = nil
  end

  def testListenerGotLine(status, message)
    return if @testSuite.nil? or @currentTest.nil?
    line = message
    line = "#{status}: #{line}" unless status.nil?
    @testSuite[@currentTest] << line
  end


  def runAnnotatedCommand(command)
    puts "\n"
    puts command.green
    IO.popen command do |io|
      io.each {||}
    end
  end

  def getPathToAllJavascriptTests (options)
    pathToAllTests = options['testPath']
    pathToAllTests = File.join(@workspace, pathToAllTests) unless pathToAllTests.start_with? @workspace
  end

  def configureJavascriptRunner(options)
    jsConfig = @javascriptRunner

    jsConfig.implementation = options['implementation']

    jsConfig.entryPoint          = "runTestsByTag"
    jsConfig.tagsAny             = options['tagsAny'].split(',') unless options['tagsAny'].nil?
    jsConfig.tagsAll             = options['tagsAll'].split(',') unless options['tagsAll'].nil?
    jsConfig.tagsNone            = options['tagsNone'].split(',') unless options['tagsNone'].nil?

    jsConfig.hardwareID          = options['hardwareID'] unless options['hardwareID'].nil?
    jsConfig.simDevice           = options['simDevice'] unless options['simDevice'].nil?
    jsConfig.simVersion          = options['simVersion'] unless options['simVersion'].nil?
    jsConfig.customJSConfigPath  = options['customJSConfigPath'] unless options['customJSConfigPath'].nil?
    jsConfig.randomSeed          = options['randomSeed'] unless options['randomSeed'].nil?

    jsConfig.writeConfiguration(getPathToAllJavascriptTests(options))
  end

  def configureJavascriptReRunner scenarioList, pathToAllTests
    jsConfig = @javascriptRunner

    jsConfig.randomSeed = nil
    jsConfig.entryPoint = "runTestsByName"
    jsConfig.scenarioList = scenarioList

    jsConfig.writeConfiguration(pathToAllTests)
  end


  def runWithOptions(options)
    gcovrWorkspace = Dir.pwd
    Dir.chdir(File.dirname(__FILE__) + '/../')

    # Sanity checks
    raise ArgumentError, 'Path to all tests was not supplied' if options['testPath'].nil?
    raise ArgumentError, 'Implementation was not supplied' if options['implementation'].nil?

    @appName = options['appName']
    @appLocation = BuildArtifacts.instance.appLocation(options['appName'])


    # set up instruments
    @instrumentsRunner.startupTimeout = options['timeout']
    @instrumentsRunner.hardwareID     = options['hardwareID']
    @instrumentsRunner.appLocation    = @appLocation
    @instrumentsRunner.simDevice      = XcodeUtils.instance.getSimulatorID(options['simDevice'], options['simVersion']) if options['hardwareID'].nil?
    @instrumentsRunner.simLanguage    = options['simLanguage'] if options['hardwareID'].nil?

    # setup listeners on instruments
    testListener = TestListener.new
    testListener.eventSink = self
    @instrumentsRunner.addListener("testListener", testListener)


    XcodeUtils.killAllSimulatorProcesses
    XcodeUtils.resetSimulator if options['hardwareID'].nil? unless options['skipSetSim']

    @testSuite = nil

    # loop until all test cases are covered.
    # we won't get the actual test list until partway through -- from a listener callback
    begin
      self.removeAnyAppCrashes

      # Setup javascript
      if @testSuite.nil?
        self.configureJavascriptRunner options
      else
        self.configureJavascriptReRunner(@testSuite.unStartedTests, getPathToAllJavascriptTests(options))
      end

      # Setup new saltinel listener
      agentListener = SaltinelAgent.new(@javascriptRunner.saltinel)
      agentListener.eventSink = self
      @instrumentsRunner.addListener("saltinelAgent", agentListener)

      @instrumentsRunner.runOnce @javascriptRunner.saltinel
      numCrashes = self.reportAnyAppCrashes
    end while not (@testSuite.nil? or @testSuite.unStartedTests.empty?)


    # DONE LOOPING
    f = File.open(BuildArtifacts.instance.junitReportFile, 'w')
    f.write(@testSuite.to_xml)
    f.close

    self.generateCoverage gcovrWorkspace if options['coverage'] #TODO: only if there are no crashes?

  end

  def removeAnyAppCrashes()
    Dir.glob("#{@crashPath}/#{@appName}*.crash").each do |crashPath|
      FileUtils.rmtree crashPath
    end
  end

  def reportAnyAppCrashes()
    crashReportsPath = BuildArtifacts.instance.crashReports
    FileUtils.mkdir_p crashReportsPath unless File.directory?(crashReportsPath)

    crashes = 0
    # TODO: glob if @appName is nil
    Dir.glob("#{@crashPath}/#{@appName}*.crash").each do |crashPath|
      # TODO: extract process name and ignore ["launchd_sim", ...]

      puts "Found a crash report from this test run at #{crashPath}"
      crashName = File.basename(crashPath, ".crash")
      crashReportPath = "#{crashReportsPath}/#{crashName}.txt"
      XcodeUtils.instance.createCrashReport(@appLocation, crashPath, crashReportPath)

      # get the first few lines for the log
      crashText = []
      file = File.open(crashReportPath, 'rb')
      file.each do |line|
        break if line.match(/^Binary Images/)
        crashText << line
      end
      file.close
      crashes += 1

      logLine = "Full crash report saved at #{crashReportPath}"
      puts logLine.red
      crashText << "\n"
      crashText << logLine

      # tell the current test suite about any failures
      unless @currentTest.nil?
        @testSuite[@currentTest].error "The target application appears to have died."
        @testSuite[@currentTest].stacktrace = crashText.join("")
        @currentTest = nil
      end
    end
    crashes
  end


  def generateCoverage(gcWorkspace)
    destinationFile      = BuildArtifacts.instance.coverageReportFile
    xcodeArtifactsFolder = BuildArtifacts.instance.xcode
    destinationPath      = BuildArtifacts.instance.objectFiles

    excludeRegex = '.*(Debug|contrib).*'
    puts "Generating automation test coverage to #{destinationFile}".green
    sleep (3) # TODO: we are waiting for the app process to complete, maybe do this a different way

    # cleanup
    FileUtils.rm destinationFile, :force => true

    # we copy all the relevant build artifacts for coverage into a second folder.  we may not need to do this.
    filePaths = []
    Find.find(xcodeArtifactsFolder) do |pathP|
      path = pathP.to_s
      if /.*\.gcda$/.match path
        filePaths << path
        pathWithoutExt = path.chomp(File.extname(path))

        filePaths << pathWithoutExt + '.d'
        filePaths << pathWithoutExt + '.dia'
        filePaths << pathWithoutExt + '.o'
        filePaths << pathWithoutExt + '.gcno'
      end
    end

    filePaths.each do |path|
      FileUtils.cp path, destinationPath
    end

    command = "gcovr -r '#{gcWorkspace}' --exclude='#{excludeRegex}' --xml '#{destinationPath}' > '#{destinationFile}'"
    self.runAnnotatedCommand(command)

  end
end
