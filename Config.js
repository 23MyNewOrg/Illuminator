// Config.js
//
// loads configuration from a generated file, provides sensible defaults

#import "buildArtifacts/environment.js"

(function() {

    var root = this,
        config = null;

    // put config in namespace of importing code
    if (typeof exports !== 'undefined') {
        config = exports;
    } else {
        config = root.config = {};
    }

    config.implementation = 'iPhone';
    config.stage = 'fake';
    config.tagsAny = []; // run all by default
    config.tagsAll = []; // none by default
    config.tagsNone = [];
    config.automatorSequenceRandomSeed = undefined;

    // setter for implementation
    config.setImplementation = function(implementation) {
        config.implementation = implementation;
    };

    // setter for hardwareID
    config.setHardwareID = function(hardwareID) {
        config.hardwareID = hardwareID;
    };
    // setter for stage
    config.setStage = function(stage) {
        config.stage = stage;
    };

    // setter for tagsAny
    config.setTagsAny = function(tagsAny) {
        config.tagsAny = tagsAny;
    };

    // setter for tagsAll
    config.setTagsAll = function(tagsAll) {
        config.tagsAll = tagsAll;
    };

    // setter for tagsNone
    config.setTagsNone = function(tagsNone) {
        config.tagsNone = tagsNone;
    };
    
    config.setCustomConfig = function(customConfig) {
        
      config.customConfig = getPlistData(customConfig);  
    };
    // setter for automatorSequenceRandomSeed
    config.setAutomatorSequenceRandomSeed = function(asrs) {
        if (asrs !== undefined) {
            config.automatorSequenceRandomSeed = parseInt(asrs);
        }
    };

    config.setAutomatorDesiredSimVersion = function(automatorDesiredSimVersion) {
        config.automatorDesiredSimVersion = automatorDesiredSimVersion;
    }

    var jsonConfig = getPlistData(automatorRoot + "/buildArtifacts/generatedConfig.plist");


    // attempt to read config -- look for VARIABLES IN GLOBAL SCOPE
    try {
        config.setImplementation(jsonConfig.implementation);
    } catch (e) {
        UIALogger.logMessage("Couldn't read implementation from generated config");
    }
    
    try {
        config.setAutomatorDesiredSimVersion(jsonConfig.automatorDesiredSimVersion);
    } catch (e) {
        
    }
    
    try {
        config.setHardwareID(jsonConfig.hardwareID)
    } catch (e) {
    }

    try {
        config.setTagsAny(jsonConfig.automatorTagsAny);
    } catch (e) {
        UIALogger.logMessage("Couldn't read automatorTagsAny from generated config");
    }

    try {
        config.setTagsAll(jsonConfig.automatorTagsAll);
    } catch (e) {
        UIALogger.logMessage("Couldn't read automatorTagsAll from generated config");
    }

    try {
        config.setTagsNone(jsonConfig.automatorTagsNone);
    } catch (e) {
        UIALogger.logMessage("Couldn't read automatorTagsNone from generated config");
    }

    try {
        config.setAutomatorSequenceRandomSeed(jsonConfig.automatorSequenceRandomSeed);
    } catch (e) {
        UIALogger.logMessage("Didn't read (optional) automatorSequenceRandomSeed from generated config");
    }


    try {
        config.setCustomConfig(jsonConfig.customConfig);
    } catch (e) {
    }



    // read config from json string
    config.readFromJSONString = function(stringJSON) {
        config.readFromObject(JSON.parse(stringJSON));
    };

    // read config from object
    config.readFromObject = function(obj) {

        for (var key in obj) {
            switch (key) {
            case "implementation":
            config.setImplementation(obj[key]);
            break;
            case "stage":
            config.setStage(obj[key]);
            case "tags":
            config.setTags(obj[key]);
            case "attributes":
            config.setAttributes(obj[key]);
            default:
            UIALogger.logDebug("Ignoring unrecognized config key '" + key + "'");
            }
        }
    };


}).call(this);
