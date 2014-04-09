#import "../common/Common.js";

////////////////////////////////////////////////////////////////////////////////////////////////////
// Appmap additions
////////////////////////////////////////////////////////////////////////////////////////////////////
appmap.createOrAugmentApp("SampleApp").withScreen("homeScreen")
    .onDevice("iPhone", homeScreenIsActive)
    .withAction("pressButton", "Press button on screen")
    .withImplementation(pressButton, "iPhone")
    
    .withAction("clearLabel", "Clear label on screen")
    .withImplementation(clearLabel, "iPhone")
    
    .withAction("verifyLabelString", "Verify label has proper string")
    .withImplementation(verifyLabelString, "iPhone")
    .withParam("labelText", "label text", true, true)

////////////////////////////////////////////////////////////////////////////////////////////////////
// Actions
////////////////////////////////////////////////////////////////////////////////////////////////////

function homeScreenIsActive() {
    try {
        target.waitUntilAccessorSuccess(function(targ) {
                return targ.frontMostApp().mainWindow().buttons()["Press Button"];
            }, 10);
        return true;
    } catch (e) {
        return false;
    }


}

function pressButton() {
    target.frontMostApp().mainWindow().buttons()["Press Button"].tap();
}

function clearLabel () {
    target.frontMostApp().mainWindow().buttons()["Clear Label"].tap();
}

function verifyLabelString(param) {	
    target.waitUntilAccessorSuccess(function(targ) {
        return targ.frontMostApp().mainWindow().staticTexts()[param.labelText];
    }, 10);
}