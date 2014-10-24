/**
 * Write data to a file
 *
 * @param path the path that should be (over)written
 * @data the data of the file to write in string format
 */
function writeToFile(path, data) {
    // type check
    switch (typeof data) {
    case "string": break;
    default: throw new TypeError("writeToFile expected data in string form, got type " + (typeof data));
    }

    var chunkSize = Math.floor(262144 * 0.74) - (path.length + 100); // `getconf ARG_MAX`, adjusted for b64

    var writeHelper = function (b64stuff, outputPath) {
        var result = target().host().performTaskWithPathArgumentsTimeout("/bin/sh", ["-c",
                                                                                     "echo \"$0\" | base64 -D -o \"$1\"",
                                                                                     b64stuff,
                                                                                     outputPath], 5);

        // be verbose if something didn't go well
        if (0 != result.exitCode) {
            UIALogger.logDebug("Exit code was nonzero: " + result.exitCode);
            UIALogger.logDebug("SDOUT: " + result.stdout);
            UIALogger.logDebug("STDERR: " + result.stderr);
            UIALogger.logDebug("I tried this command: ");
            UIALogger.logDebug("/bin/sh -c \"echo \\\"$0\\\" | base64 -D -o \\\$1\\\" " + b64stuff + " " + outputPath);
            return false;
        }
        return true;
    }

    var result = true;
    if (data.length < chunkSize) {
        var b64data = Base64.encode(data);
        UIALogger.logDebug("Writing " + data.length + " bytes to " + path + " as " + b64data.length + " bytes of b64");
        result = result && writeHelper(b64data, path);

    } else {
        // split into chunks to avoid making the command line too long
        splitRegex = function(str, len) {
            var regex = new RegExp('[\\s\\S]{1,' + len + '}', 'g');
            return str.match(regex);
        }

        // write each chunk to a file
        var chunks = splitRegex(data, chunkSize);
        var chunkFiles = [];
        for (var i = 0; i < chunks.length; ++i) {
            var chunk = chunks[i];
            var chunkFile = path + ".chunk" + i;
            var b64data = Base64.encode(chunk);
            UIALogger.logDebug("Writing " + chunk.length + " bytes to " + chunkFile + " as " + b64data.length + " bytes of b64");
            result = result && writeHelper(b64data, chunkFile);
            chunkFiles.push(chunkFile);
        }

        // concatenate all the chunks
        var unchunkCmd = "cat \"" + chunkFiles.join("\" \"") + "\" > \"$0\"";
        UIALogger.logDebug("Concatenating and deleting " + chunkFiles.length + " chunks, writing " + path);
        target().host().performTaskWithPathArgumentsTimeout("/bin/sh", ["-c", unchunkCmd, path], 5);
        target().host().performTaskWithPathArgumentsTimeout("/bin/rm", chunkFiles, 5);
    }

    return result;
}

// attempt to parse JSON, raise helpful error if it fails
function _getJSONFromShell(owner, output) {
    var jsonOutput;
    try {
        jsonOutput = JSON.parse(output.stdout);
    } catch(e) {
        throw new Error(owner + " gave bad JSON: ```" + output.stdout + "```");
    }

    return jsonOutput;
}

function getJSONData(path) {
    return _getJSONFromShell("cat " + path, target().host().performTaskWithPathArgumentsTimeout("/bin/cat", [path], 30));
}

function getPlistData(path) {
    var jsonOutput;
    var scriptPath = IlluminatorRootDirectory + "/scripts/plist_to_json.sh";
    UIALogger.logDebug("Running " + scriptPath + " '" + path + "'");

    return _getJSONFromShell("plist_to_json.sh", target().host().performTaskWithPathArgumentsTimeout(scriptPath, [path], 30));
}
