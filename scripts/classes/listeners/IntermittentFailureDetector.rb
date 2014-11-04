
require File.join(File.expand_path(File.dirname(__FILE__)), 'SaltinelListener.rb')

module IntermittentFailureDetectorEventSink

  def intermittentFailureDetectorTriggered
    puts "  +++ If you're seeing this, #{self.class.name}.#{__method__} was not overridden"
  end

end

# IntermittentFailureDetector monitors the logs for things that indicate a transient failure to start instruments
#  - UIATargetHasGoneAWOLException
#  - etc
class IntermittentFailureDetector < SaltinelListener

  attr_accessor :eventSink

  def onInit
    @alreadyStarted = false
  end

  def trigger
    # assume developer has set eventSink already
    @eventSink.startDetectorTriggered unless @alreadyStarted
    @alreadyStarted = true
  end

  def receive message
    super # run the SaltinelListener processor

    # error cases that should trigger a restart
    self.trigger if /Automation Instrument ran into an exception while trying to run the script.  UIATargetHasGoneAWOLException/ =~ message.fullLine
  end

  def onSaltinel innerMessage
    # no cases yet
  end

  def onAutomationFinished
  end

end
